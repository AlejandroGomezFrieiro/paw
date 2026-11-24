// paw-ara: the host side of ARA 2 for paw, as an attachment
// (crates/paw-plugins/include/paw_attach.h).
//
// paw offers each CLAP plugin that it makes to this library, after the
// plugin's init and before its activate. A plugin with the ARA extension
// gets a document of its own: one musical context (the song's tempo and
// signatures), one region sequence (the part), and for each audio clip of
// the part an audio source (the clip's file), an audio modification (the
// clip's edits in the plugin) and a playback region (where the clip plays).
// The plugin instance is bound to the document with all three roles:
// playback renderer, editor renderer and editor view.
//
// paw gives the part's clips as JSON (`paw.clips`) each time they change,
// asks for the ARA archive when it saves the project (`paw.file.save`), and
// gives it back when it makes the plugin again (`paw.file.load`). The
// extension's Lua asks for the notes that the plugin found (`ara.notes`) and
// for a summary (`ara.status`).
//
// Everything here runs on the main thread of the process that hosts the
// plugin, except the audio reader, which the plugin may use from any thread.

#include "paw_attach.h"

#include "ARA_API/ARACLAP.h"
#include "ARA_API/ARAInterface.h"

#include <nlohmann/json.hpp>

#include <algorithm>
#include <cmath>
#include <cstring>
#include <map>
#include <memory>
#include <mutex>
#include <set>
#include <string>
#include <vector>

using namespace ARA;
using json = nlohmann::json;

namespace {

constexpr ARAAPIGeneration kGeneration = kARAAPIGeneration_2_0_Final;
constexpr ARAPlugInInstanceRoleFlags kRoles = kARAPlaybackRendererRole | kARAEditorRendererRole | kARAEditorViewRole;
// The head of the file that paw keeps: the archive's ID follows it on its own line.
constexpr const char *kFileMagic = "paw-ara 1\n";

struct Bridge;

// The sound of a clip's file, read through paw.
struct Source {
    Bridge *bridge = nullptr;
    std::string file;
    std::string persistentID;
    void *audio = nullptr;
    paw_audio_info info{};
    ARAAudioSourceRef ref = nullptr;
    int users = 0;
    bool analyzing = false;
    float progress = 0.0f;
};

// One clip of the part: its audio modification and playback region.
struct Clip {
    int64_t id = 0;
    std::string name;
    std::string persistentID;
    Source *source = nullptr;
    ARAAudioModificationRef modification = nullptr;
    ARAPlaybackRegionRef region = nullptr;
    ARAPlaybackRegionProperties props{};
    double start = 0, length = 0, offset = 0, stretch = 1;
};

struct Reader {
    Source *source;
    bool use64;
};

// What the host gives the plugin of the musical context.
struct ContentReader {
    ARAContentType type;
    std::vector<ARAContentTempoEntry> tempo;
    std::vector<ARAContentBarSignature> signatures;
};

struct Archive {
    std::vector<uint8_t> bytes;
    std::string id;
};

struct Bridge {
    const paw_attach_host *host = nullptr;
    const clap_plugin_t *plugin = nullptr;
    const ARAFactory *factory = nullptr;
    const ARADocumentControllerInstance *dc = nullptr;
    const ARAPlugInExtensionInstance *instance = nullptr;
    ARAMusicalContextRef context = nullptr;
    ARARegionSequenceRef sequence = nullptr;
    std::string partName = "Part";
    std::map<std::string, std::unique_ptr<Source>> sources;
    std::map<int64_t, std::unique_ptr<Clip>> clips;
    std::vector<ARAContentTempoEntry> tempo;
    std::vector<ARAContentBarSignature> signatures;
    // The archive that paw gave, until the document has the objects to restore it into.
    std::unique_ptr<Archive> pending;
    bool restored = false;
    std::string lastError;
    // The plugin is stopped for this call: `paw.clips` that adds or takes
    // away a region asks paw to call it again while the plugin is stopped.
    bool stopped = false;

    const ARADocumentControllerInterface *api() const { return dc->documentControllerInterface; }
    ARADocumentControllerRef ref() const { return dc->documentControllerRef; }
};

// --- what the host gives the plugin --------------------------------------------

Bridge *bridgeOf(void *ref) { return static_cast<Bridge *>(ref); }

ARAAudioReaderHostRef ARA_CALL createAudioReader(ARAAudioAccessControllerHostRef, ARAAudioSourceHostRef source, ARABool use64) {
    return reinterpret_cast<ARAAudioReaderHostRef>(new Reader{reinterpret_cast<Source *>(source), use64 != kARAFalse});
}

ARABool ARA_CALL readAudioSamples(ARAAudioAccessControllerHostRef controller, ARAAudioReaderHostRef readerRef,
                                  ARASamplePosition position, ARASampleCount count, void *const buffers[]) {
    auto reader = reinterpret_cast<Reader *>(readerRef);
    auto source = reader->source;
    auto host = bridgeOf(controller)->host;
    const uint32_t channels = source->info.channels;
    if (!reader->use64) {
        std::vector<float *> outs(channels);
        for (uint32_t c = 0; c < channels; ++c) outs[c] = static_cast<float *>(buffers[c]);
        return host->audio_read(source->audio, position, count, outs.data(), channels) ? kARATrue : kARAFalse;
    }
    std::vector<std::vector<float>> temp(channels, std::vector<float>(static_cast<size_t>(count)));
    std::vector<float *> outs(channels);
    for (uint32_t c = 0; c < channels; ++c) outs[c] = temp[c].data();
    if (!host->audio_read(source->audio, position, count, outs.data(), channels)) return kARAFalse;
    for (uint32_t c = 0; c < channels; ++c) {
        auto out = static_cast<double *>(buffers[c]);
        for (ARASampleCount i = 0; i < count; ++i) out[i] = temp[c][static_cast<size_t>(i)];
    }
    return kARATrue;
}

void ARA_CALL destroyAudioReader(ARAAudioAccessControllerHostRef, ARAAudioReaderHostRef reader) {
    delete reinterpret_cast<Reader *>(reader);
}

const ARAAudioAccessControllerInterface audioAccess = {
    ARA_IMPLEMENTED_STRUCT_SIZE(ARAAudioAccessControllerInterface, destroyAudioReader),
    &createAudioReader, &readAudioSamples, &destroyAudioReader};

ARASize ARA_CALL getArchiveSize(ARAArchivingControllerHostRef, ARAArchiveReaderHostRef reader) {
    return reinterpret_cast<Archive *>(reader)->bytes.size();
}

ARABool ARA_CALL readBytesFromArchive(ARAArchivingControllerHostRef, ARAArchiveReaderHostRef reader, ARASize position,
                                      ARASize length, ARAByte buffer[]) {
    auto &bytes = reinterpret_cast<Archive *>(reader)->bytes;
    if (position + length > bytes.size()) return kARAFalse;
    std::memcpy(buffer, bytes.data() + position, length);
    return kARATrue;
}

ARABool ARA_CALL writeBytesToArchive(ARAArchivingControllerHostRef, ARAArchiveWriterHostRef writer, ARASize position,
                                     ARASize length, const ARAByte buffer[]) {
    auto &bytes = reinterpret_cast<Archive *>(writer)->bytes;
    if (bytes.size() < position + length) bytes.resize(position + length);
    std::memcpy(bytes.data() + position, buffer, length);
    return kARATrue;
}

void ARA_CALL archivingProgress(ARAArchivingControllerHostRef, float) {}

ARAPersistentID ARA_CALL getDocumentArchiveID(ARAArchivingControllerHostRef, ARAArchiveReaderHostRef reader) {
    return reinterpret_cast<Archive *>(reader)->id.c_str();
}

const ARAArchivingControllerInterface archiving = {
    ARA_IMPLEMENTED_STRUCT_SIZE(ARAArchivingControllerInterface, getDocumentArchiveID),
    &getArchiveSize, &readBytesFromArchive, &writeBytesToArchive, &archivingProgress, &archivingProgress,
    &getDocumentArchiveID};

ARABool ARA_CALL isMusicalContextContentAvailable(ARAContentAccessControllerHostRef, ARAMusicalContextHostRef, ARAContentType type) {
    return (type == kARAContentTypeTempoEntries || type == kARAContentTypeBarSignatures) ? kARATrue : kARAFalse;
}

ARAContentGrade ARA_CALL getMusicalContextContentGrade(ARAContentAccessControllerHostRef, ARAMusicalContextHostRef, ARAContentType) {
    return kARAContentGradeAdjusted;
}

ARAContentReaderHostRef ARA_CALL createMusicalContextContentReader(ARAContentAccessControllerHostRef controller,
                                                                   ARAMusicalContextHostRef, ARAContentType type,
                                                                   const ARAContentTimeRange *) {
    auto bridge = bridgeOf(controller);
    if (type == kARAContentTypeTempoEntries)
        return reinterpret_cast<ARAContentReaderHostRef>(new ContentReader{type, bridge->tempo, {}});
    if (type == kARAContentTypeBarSignatures)
        return reinterpret_cast<ARAContentReaderHostRef>(new ContentReader{type, {}, bridge->signatures});
    return nullptr;
}

ARABool ARA_CALL isAudioSourceContentAvailable(ARAContentAccessControllerHostRef, ARAAudioSourceHostRef, ARAContentType) {
    return kARAFalse;
}

ARAContentGrade ARA_CALL getAudioSourceContentGrade(ARAContentAccessControllerHostRef, ARAAudioSourceHostRef, ARAContentType) {
    return kARAContentGradeInitial;
}

ARAContentReaderHostRef ARA_CALL createAudioSourceContentReader(ARAContentAccessControllerHostRef, ARAAudioSourceHostRef,
                                                                ARAContentType, const ARAContentTimeRange *) {
    return nullptr;
}

ARAInt32 ARA_CALL getContentReaderEventCount(ARAContentAccessControllerHostRef, ARAContentReaderHostRef ref) {
    auto reader = reinterpret_cast<ContentReader *>(ref);
    return static_cast<ARAInt32>(reader->type == kARAContentTypeTempoEntries ? reader->tempo.size() : reader->signatures.size());
}

const void *ARA_CALL getContentReaderDataForEvent(ARAContentAccessControllerHostRef, ARAContentReaderHostRef ref, ARAInt32 index) {
    auto reader = reinterpret_cast<ContentReader *>(ref);
    if (reader->type == kARAContentTypeTempoEntries) return &reader->tempo[static_cast<size_t>(index)];
    return &reader->signatures[static_cast<size_t>(index)];
}

void ARA_CALL destroyContentReader(ARAContentAccessControllerHostRef, ARAContentReaderHostRef ref) {
    delete reinterpret_cast<ContentReader *>(ref);
}

const ARAContentAccessControllerInterface contentAccess = {
    ARA_IMPLEMENTED_STRUCT_SIZE(ARAContentAccessControllerInterface, destroyContentReader),
    &isMusicalContextContentAvailable, &getMusicalContextContentGrade, &createMusicalContextContentReader,
    &isAudioSourceContentAvailable, &getAudioSourceContentGrade, &createAudioSourceContentReader,
    &getContentReaderEventCount, &getContentReaderDataForEvent, &destroyContentReader};

void ARA_CALL analysisProgress(ARAModelUpdateControllerHostRef, ARAAudioSourceHostRef sourceRef, ARAAnalysisProgressState state, float value) {
    auto source = reinterpret_cast<Source *>(sourceRef);
    source->analyzing = state != kARAAnalysisProgressCompleted;
    source->progress = value;
}

void ARA_CALL sourceContentChanged(ARAModelUpdateControllerHostRef, ARAAudioSourceHostRef, const ARAContentTimeRange *, ARAContentUpdateFlags) {}
void ARA_CALL modificationContentChanged(ARAModelUpdateControllerHostRef, ARAAudioModificationHostRef, const ARAContentTimeRange *, ARAContentUpdateFlags) {}
void ARA_CALL regionContentChanged(ARAModelUpdateControllerHostRef, ARAPlaybackRegionHostRef, const ARAContentTimeRange *, ARAContentUpdateFlags) {}
void ARA_CALL documentDataChanged(ARAModelUpdateControllerHostRef) {}

const ARAModelUpdateControllerInterface modelUpdate = {
    ARA_IMPLEMENTED_STRUCT_SIZE(ARAModelUpdateControllerInterface, notifyDocumentDataChanged),
    &analysisProgress, &sourceContentChanged, &modificationContentChanged, &regionContentChanged, &documentDataChanged};

// --- ARA once for each factory --------------------------------------------------

std::mutex factoriesLock;
std::map<const ARAFactory *, int> factories;

void useFactory(const ARAFactory *factory) {
    std::lock_guard<std::mutex> lock(factoriesLock);
    if (factories[factory]++ == 0) {
        const ARAInterfaceConfiguration config = {
            ARA_IMPLEMENTED_STRUCT_SIZE(ARAInterfaceConfiguration, assertFunctionAddress), kGeneration, nullptr};
        factory->initializeARAWithConfiguration(&config);
    }
}

void releaseFactory(const ARAFactory *factory) {
    std::lock_guard<std::mutex> lock(factoriesLock);
    if (--factories[factory] == 0) {
        factory->uninitializeARA();
        factories.erase(factory);
    }
}

// --- the document ---------------------------------------------------------------

void setTempo(Bridge *b, const json &clips) {
    b->tempo.clear();
    for (auto &point : clips.value("tempo", json::array()))
        b->tempo.push_back({point.value("seconds", 0.0), point.value("beat", 0.0)});
    // ARA wants two points at least.
    if (b->tempo.size() < 2) b->tempo = {{0.0, 0.0}, {0.5, 1.0}};
    b->signatures.clear();
    for (auto &sig : clips.value("signatures", json::array()))
        b->signatures.push_back({sig.value("num", 4), sig.value("den", 4), sig.value("beat", 0.0)});
    if (b->signatures.empty()) b->signatures.push_back({4, 4, 0.0});
}

Source *openSource(Bridge *b, const std::string &file) {
    auto &slot = b->sources[file];
    if (slot) return slot.get();
    auto source = std::make_unique<Source>();
    source->bridge = b;
    source->file = file;
    source->persistentID = "file:" + file;
    source->audio = b->host->audio_open(file.c_str(), &source->info);
    if (!source->audio) {
        b->sources.erase(file);
        return nullptr;
    }
    ARAAudioSourceProperties props{};
    props.structSize = ARA_IMPLEMENTED_STRUCT_SIZE(ARAAudioSourceProperties, merits64BitSamples);
    auto slash = file.find_last_of('/');
    props.name = file.c_str() + (slash == std::string::npos ? 0 : slash + 1);
    props.persistentID = source->persistentID.c_str();
    props.sampleCount = source->info.frames;
    props.sampleRate = source->info.sample_rate;
    props.channelCount = static_cast<ARAChannelCount>(source->info.channels);
    props.merits64BitSamples = kARAFalse;
    source->ref = b->api()->createAudioSource(b->ref(), reinterpret_cast<ARAAudioSourceHostRef>(source.get()), &props);
    slot = std::move(source);
    return slot.get();
}

ARAPlaybackRegionProperties regionProps(Bridge *b, const Clip &clip) {
    ARAPlaybackRegionProperties props{};
    props.structSize = ARA_IMPLEMENTED_STRUCT_SIZE(ARAPlaybackRegionProperties, color);
    props.transformationFlags = kARAPlaybackTransformationNoChanges;
    props.startInModificationTime = clip.offset;
    props.durationInModificationTime = clip.length;
    // A clip that plays its file at another speed is stretched by the
    // plugin when it can; else it plays at the speed of the file.
    if (clip.stretch > 0 && std::fabs(clip.stretch - 1.0) > 1e-9 &&
        (b->factory->supportedPlaybackTransformationFlags & kARAPlaybackTransformationTimestretch) != 0) {
        props.transformationFlags = kARAPlaybackTransformationTimestretch;
        props.durationInModificationTime = clip.length / clip.stretch;
    }
    props.startInPlaybackTime = clip.start;
    props.durationInPlaybackTime = clip.length;
    props.regionSequenceRef = b->sequence;
    props.name = clip.name.c_str();
    return props;
}

bool sameRegion(const ARAPlaybackRegionProperties &a, const ARAPlaybackRegionProperties &b) {
    return a.transformationFlags == b.transformationFlags && a.startInModificationTime == b.startInModificationTime &&
           a.durationInModificationTime == b.durationInModificationTime && a.startInPlaybackTime == b.startInPlaybackTime &&
           a.durationInPlaybackTime == b.durationInPlaybackTime;
}

struct Wanted {
    int64_t id;
    std::string name, file;
    double start, length, offset, stretch;
};

std::vector<Wanted> wantedClips(const json &doc) {
    std::vector<Wanted> out;
    for (auto &c : doc.value("clips", json::array())) {
        if (c.value("muted", false)) continue;
        out.push_back({c.value("id", int64_t{0}), c.value("name", std::string()), c.value("file", std::string()),
                       c.value("start", 0.0), c.value("length", 0.0), c.value("offset", 0.0), c.value("stretch", 1.0)});
    }
    return out;
}

// Whether making the document as `doc` says adds or takes away a region,
// which the plugin only allows while it is not active.
bool regionsChange(Bridge *b, const std::vector<Wanted> &wanted) {
    std::set<int64_t> ids;
    for (auto &w : wanted) {
        ids.insert(w.id);
        auto it = b->clips.find(w.id);
        if (it == b->clips.end() || it->second->source->file != w.file) return true;
    }
    for (auto &[id, clip] : b->clips)
        if (!ids.count(id)) return true;
    return false;
}

void dropClip(Bridge *b, Clip &clip) {
    auto inst = b->instance;
    if (inst->playbackRendererInterface) inst->playbackRendererInterface->removePlaybackRegion(inst->playbackRendererRef, clip.region);
    if (inst->editorRendererInterface) inst->editorRendererInterface->removePlaybackRegion(inst->editorRendererRef, clip.region);
    b->api()->destroyPlaybackRegion(b->ref(), clip.region);
    b->api()->destroyAudioModification(b->ref(), clip.modification);
    clip.source->users--;
}

// Make the document as paw says. Returns false with `lastError` set when a
// file could not be read.
bool apply(Bridge *b, const json &doc, const std::vector<Wanted> &wanted) {
    auto api = b->api();
    auto ref = b->ref();
    std::string missing;
    b->partName = doc.value("part", json::object()).value("name", std::string("Part"));
    setTempo(b, doc);

    // Sources that no clip uses any more stop being read before they go.
    std::set<std::string> files;
    for (auto &w : wanted) files.insert(w.file);
    std::vector<Source *> dropping;
    for (auto &[file, source] : b->sources)
        if (!files.count(file)) {
            api->enableAudioSourceSamplesAccess(ref, source->ref, kARAFalse);
            dropping.push_back(source.get());
        }

    api->beginEditing(ref);
    api->updateMusicalContextContent(ref, b->context, nullptr, kARAContentUpdateEverythingChanged);
    ARARegionSequenceProperties seq{};
    seq.structSize = ARA_IMPLEMENTED_STRUCT_SIZE(ARARegionSequenceProperties, color);
    seq.name = b->partName.c_str();
    seq.musicalContextRef = b->context;
    api->updateRegionSequenceProperties(ref, b->sequence, &seq);

    // A clip stays when paw still has it, with the same file.
    for (auto it = b->clips.begin(); it != b->clips.end();) {
        bool keep = false;
        for (auto &w : wanted)
            if (w.id == it->first && w.file == it->second->source->file) keep = true;
        if (!keep) {
            dropClip(b, *it->second);
            it = b->clips.erase(it);
        } else {
            ++it;
        }
    }
    for (auto *source : dropping) {
        api->destroyAudioSource(ref, source->ref);
        b->host->audio_close(source->audio);
        b->sources.erase(source->file);
    }

    std::vector<Source *> opened;
    for (auto &w : wanted) {
        auto it = b->clips.find(w.id);
        if (it != b->clips.end()) {
            auto &clip = *it->second;
            clip.name = w.name;
            clip.start = w.start, clip.length = w.length, clip.offset = w.offset, clip.stretch = w.stretch;
            auto props = regionProps(b, clip);
            if (!sameRegion(props, clip.props)) {
                api->updatePlaybackRegionProperties(ref, clip.region, &props);
                clip.props = props;
            }
            continue;
        }
        bool fresh = !b->sources.count(w.file);
        auto source = openSource(b, w.file);
        if (!source) {
            missing = w.file;
            continue;
        }
        if (fresh) opened.push_back(source);
        auto clip = std::make_unique<Clip>();
        clip->id = w.id;
        clip->name = w.name;
        clip->persistentID = "clip:" + std::to_string(w.id);
        clip->source = source;
        clip->start = w.start, clip->length = w.length, clip->offset = w.offset, clip->stretch = w.stretch;
        ARAAudioModificationProperties mod{};
        mod.structSize = ARA_IMPLEMENTED_STRUCT_SIZE(ARAAudioModificationProperties, persistentID);
        mod.name = clip->name.c_str();
        mod.persistentID = clip->persistentID.c_str();
        clip->modification = api->createAudioModification(ref, source->ref, reinterpret_cast<ARAAudioModificationHostRef>(clip.get()), &mod);
        clip->props = regionProps(b, *clip);
        clip->region = api->createPlaybackRegion(ref, clip->modification, reinterpret_cast<ARAPlaybackRegionHostRef>(clip.get()), &clip->props);
        source->users++;
        auto inst = b->instance;
        if (inst->playbackRendererInterface) inst->playbackRendererInterface->addPlaybackRegion(inst->playbackRendererRef, clip->region);
        if (inst->editorRendererInterface) inst->editorRendererInterface->addPlaybackRegion(inst->editorRendererRef, clip->region);
        b->clips[w.id] = std::move(clip);
    }

    // The archive paw kept goes into the objects it was made of, once they exist.
    if (b->pending && !b->clips.empty()) {
        if (!api->restoreObjectsFromArchive(ref, reinterpret_cast<ARAArchiveReaderHostRef>(b->pending.get()), nullptr))
            b->lastError = "the plugin could not read its archive";
        b->pending.reset();
        b->restored = true;
    }
    api->endEditing(ref);
    for (auto *source : opened) api->enableAudioSourceSamplesAccess(ref, source->ref, kARATrue);
    api->notifyModelUpdates(ref);
    if (!missing.empty()) {
        b->lastError = "could not read " + missing;
        return false;
    }
    return true;
}

// --- answers --------------------------------------------------------------------

void reply(void *out, paw_write_fn write, const std::string &text) {
    write(out, reinterpret_cast<const uint8_t *>(text.data()), text.size());
}

int fail(void *out, paw_write_fn write, const std::string &why) {
    reply(out, write, why);
    return PAW_CALL_FAILED;
}

int onClips(Bridge *b, const uint8_t *data, size_t size, void *out, paw_write_fn write) {
    json doc = json::parse(data, data + size, nullptr, false);
    if (doc.is_discarded()) return fail(out, write, "the clips are not JSON");
    auto wanted = wantedClips(doc);
    if (!b->stopped && regionsChange(b, wanted)) {
        b->stopped = true;
        return PAW_CALL_STOPPED;
    }
    b->stopped = false;
    if (!apply(b, doc, wanted)) return fail(out, write, b->lastError);
    return PAW_CALL_DONE;
}

int onSave(Bridge *b, void *out, paw_write_fn write) {
    if (b->clips.empty() && !b->pending) return PAW_CALL_DONE;
    // An archive that was never restored (its clips are not here now) is kept as it was.
    if (b->pending && b->clips.empty()) {
        reply(out, write, std::string(kFileMagic) + b->pending->id + "\n");
        write(out, b->pending->bytes.data(), b->pending->bytes.size());
        return PAW_CALL_DONE;
    }
    Archive archive;
    if (!b->api()->storeObjectsToArchive(b->ref(), reinterpret_cast<ARAArchiveWriterHostRef>(&archive), nullptr))
        return fail(out, write, "the plugin could not write its archive");
    reply(out, write, std::string(kFileMagic) + b->factory->documentArchiveID + "\n");
    write(out, archive.bytes.data(), archive.bytes.size());
    return PAW_CALL_DONE;
}

int onLoad(Bridge *b, const uint8_t *data, size_t size, void *out, paw_write_fn write) {
    std::string head(reinterpret_cast<const char *>(data), std::min(size, size_t{4096}));
    const std::string magic = kFileMagic;
    if (head.compare(0, magic.size(), magic) != 0) return fail(out, write, "the ARA file is not one paw wrote");
    auto end = head.find('\n', magic.size());
    if (end == std::string::npos) return fail(out, write, "the ARA file has no archive ID");
    auto archive = std::make_unique<Archive>();
    archive->id = head.substr(magic.size(), end - magic.size());
    archive->bytes.assign(data + end + 1, data + size);
    // An archive of another plugin, or of a version it cannot read, is kept and not given.
    bool known = archive->id == b->factory->documentArchiveID;
    for (ARASize i = 0; i < b->factory->compatibleDocumentArchiveIDsCount; ++i)
        if (archive->id == b->factory->compatibleDocumentArchiveIDs[i]) known = true;
    if (!known) return fail(out, write, "the ARA archive is from " + archive->id + ", which this plugin cannot read");
    b->pending = std::move(archive);
    b->restored = false;
    return PAW_CALL_DONE;
}

json noteJson(const ARAContentNote &note, int64_t clip) {
    return {{"clip", clip},
            {"pitch", note.pitchNumber},
            {"frequency", note.frequency},
            {"volume", note.volume},
            {"start", note.startPosition},
            {"duration", note.noteDuration}};
}

// The notes the plugin found in each clip, in seconds of the song. While the
// plugin is still at work: `{ "pending": true, "progress": 0.4 }`.
int onNotes(Bridge *b, void *out, paw_write_fn write) {
    auto api = b->api();
    auto ref = b->ref();
    api->notifyModelUpdates(ref);
    json notes = json::array();
    bool pending = false;
    float progress = 1.0f;
    for (auto &[id, clip] : b->clips) {
        if (!api->isPlaybackRegionContentAvailable(ref, clip->region, kARAContentTypeNotes)) {
            auto source = clip->source;
            if (api->isAudioSourceContentAnalysisIncomplete(ref, source->ref, kARAContentTypeNotes)) {
                pending = true;
                progress = std::min(progress, source->progress);
                if (!source->analyzing) {
                    const ARAContentType types[] = {kARAContentTypeNotes};
                    api->requestAudioSourceContentAnalysis(ref, source->ref, 1, types);
                    source->analyzing = true;
                }
            }
            continue;
        }
        auto reader = api->createPlaybackRegionContentReader(ref, clip->region, kARAContentTypeNotes, nullptr);
        if (!reader) continue;
        auto count = api->getContentReaderEventCount(ref, reader);
        for (ARAInt32 i = 0; i < count; ++i) {
            auto note = static_cast<const ARAContentNote *>(api->getContentReaderDataForEvent(ref, reader, i));
            if (note) notes.push_back(noteJson(*note, id));
        }
        api->destroyContentReader(ref, reader);
    }
    json answer = pending ? json{{"pending", true}, {"progress", progress}} : json{{"notes", notes}};
    reply(out, write, answer.dump());
    return PAW_CALL_DONE;
}

// paw asks whether the plugin works on something that it shows later: "1"
// while it analyzes a clip, so that the stepped engine of the tests waits.
int onBusy(Bridge *b, void *out, paw_write_fn write) {
    b->api()->notifyModelUpdates(b->ref());
    bool busy = false;
    for (auto &[id, clip] : b->clips) busy = busy || clip->source->analyzing;
    reply(out, write, busy ? "1" : "0");
    return PAW_CALL_DONE;
}

int onStatus(Bridge *b, void *out, paw_write_fn write) {
    b->api()->notifyModelUpdates(b->ref());
    json clips = json::array();
    for (auto &[id, clip] : b->clips)
        clips.push_back({{"id", id}, {"name", clip->name}, {"file", clip->source->file}, {"start", clip->start},
                         {"length", clip->length}, {"analyzing", clip->source->analyzing}});
    json types = json::array();
    for (ARASize i = 0; i < b->factory->analyzeableContentTypesCount; ++i) types.push_back(b->factory->analyzeableContentTypes[i]);
    json status = {{"plugin", b->factory->plugInName ? b->factory->plugInName : ""},
                   {"manufacturer", b->factory->manufacturerName ? b->factory->manufacturerName : ""},
                   {"version", b->factory->version ? b->factory->version : ""},
                   {"archive_id", b->factory->documentArchiveID ? b->factory->documentArchiveID : ""},
                   {"notes", std::find(types.begin(), types.end(), int(kARAContentTypeNotes)) != types.end()},
                   {"timestretch", (b->factory->supportedPlaybackTransformationFlags & kARAPlaybackTransformationTimestretch) != 0},
                   {"part", b->partName},
                   {"sources", b->sources.size()},
                   {"clips", clips},
                   {"restored", b->restored},
                   {"error", b->lastError}};
    reply(out, write, status.dump());
    return PAW_CALL_DONE;
}

// --- the attachment -------------------------------------------------------------

void *attach(const paw_attach_host *host, const char *format, const void *pluginPtr) {
    if (!host || host->abi != PAW_ATTACH_ABI || std::strcmp(format, "clap") != 0) return nullptr;
    auto plugin = static_cast<const clap_plugin_t *>(pluginPtr);
    if (!plugin->get_extension) return nullptr;
    auto ext = static_cast<const clap_ara_plugin_extension_t *>(plugin->get_extension(plugin, CLAP_EXT_ARA_PLUGINEXTENSION));
    if (!ext || !ext->get_factory || !ext->bind_to_document_controller) return nullptr;
    auto factory = ext->get_factory(plugin);
    if (!factory || factory->lowestSupportedApiGeneration > kGeneration || factory->highestSupportedApiGeneration < kGeneration)
        return nullptr;

    auto b = std::make_unique<Bridge>();
    b->host = host;
    b->plugin = plugin;
    b->factory = factory;
    useFactory(factory);

    static ARADocumentControllerHostInstance hostInstance{};
    hostInstance.structSize = ARA_IMPLEMENTED_STRUCT_SIZE(ARADocumentControllerHostInstance, playbackControllerInterface);
    hostInstance.audioAccessControllerInterface = &audioAccess;
    hostInstance.archivingControllerInterface = &archiving;
    hostInstance.contentAccessControllerInterface = &contentAccess;
    hostInstance.modelUpdateControllerInterface = &modelUpdate;
    // The controller refs carry the bridge; the instance is copied by the plugin.
    ARADocumentControllerHostInstance mine = hostInstance;
    mine.audioAccessControllerHostRef = reinterpret_cast<ARAAudioAccessControllerHostRef>(b.get());
    mine.archivingControllerHostRef = reinterpret_cast<ARAArchivingControllerHostRef>(b.get());
    mine.contentAccessControllerHostRef = reinterpret_cast<ARAContentAccessControllerHostRef>(b.get());
    mine.modelUpdateControllerHostRef = reinterpret_cast<ARAModelUpdateControllerHostRef>(b.get());

    ARADocumentProperties docProps{ARA_IMPLEMENTED_STRUCT_SIZE(ARADocumentProperties, name), "paw"};
    b->dc = factory->createDocumentControllerWithDocument(&mine, &docProps);
    if (!b->dc) {
        releaseFactory(factory);
        return nullptr;
    }
    setTempo(b.get(), json::object());
    auto api = b->api();
    api->beginEditing(b->ref());
    ARAMusicalContextProperties ctx{};
    ctx.structSize = ARA_IMPLEMENTED_STRUCT_SIZE(ARAMusicalContextProperties, color);
    b->context = api->createMusicalContext(b->ref(), reinterpret_cast<ARAMusicalContextHostRef>(b.get()), &ctx);
    ARARegionSequenceProperties seq{};
    seq.structSize = ARA_IMPLEMENTED_STRUCT_SIZE(ARARegionSequenceProperties, color);
    seq.name = b->partName.c_str();
    seq.musicalContextRef = b->context;
    b->sequence = api->createRegionSequence(b->ref(), reinterpret_cast<ARARegionSequenceHostRef>(b.get()), &seq);
    api->endEditing(b->ref());

    b->instance = ext->bind_to_document_controller(plugin, b->ref(), kRoles, kRoles);
    if (!b->instance) {
        api->destroyDocumentController(b->ref());
        releaseFactory(factory);
        return nullptr;
    }
    return b.release();
}

int call(void *handle, const char *method, const uint8_t *data, size_t size, void *out, paw_write_fn write) {
    auto b = static_cast<Bridge *>(handle);
    std::string m = method;
    if (m == "paw.clips") return onClips(b, data, size, out, write);
    if (m == "paw.file.save") return onSave(b, out, write);
    if (m == "paw.file.load") return size == 0 ? PAW_CALL_DONE : onLoad(b, data, size, out, write);
    if (m == "paw.busy") return onBusy(b, out, write);
    if (m == "ara.notes") return onNotes(b, out, write);
    if (m == "ara.status") return onStatus(b, out, write);
    return PAW_CALL_UNKNOWN;
}

void detach(void *handle) {
    auto b = static_cast<Bridge *>(handle);
    auto api = b->api();
    auto ref = b->ref();
    for (auto &[file, source] : b->sources) api->enableAudioSourceSamplesAccess(ref, source->ref, kARAFalse);
    api->beginEditing(ref);
    for (auto &[id, clip] : b->clips) dropClip(b, *clip);
    b->clips.clear();
    for (auto &[file, source] : b->sources) {
        api->destroyAudioSource(ref, source->ref);
        b->host->audio_close(source->audio);
    }
    b->sources.clear();
    api->destroyRegionSequence(ref, b->sequence);
    api->destroyMusicalContext(ref, b->context);
    api->endEditing(ref);
    api->destroyDocumentController(ref);
    releaseFactory(b->factory);
    delete b;
}

const paw_attachment entry = {PAW_ATTACH_ABI, "ara", &attach, &call, &detach};

}  // namespace

extern "C" __attribute__((visibility("default"))) const paw_attachment *paw_attachment_entry(void) { return &entry; }

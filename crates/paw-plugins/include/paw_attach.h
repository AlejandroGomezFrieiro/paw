/* paw_attach.h: the interface between paw and an attachment.
 *
 * An attachment is a native library that an extension ships. paw loads it
 * into each process that hosts plugins (`paw.plugins.attach(path)`), and
 * offers it each CLAP plugin that paw makes, after the plugin's `init` and
 * before its `activate`. An attachment that takes the plugin can reach the
 * plugin's own extensions (ARA, for one), answer `device_call` methods for
 * the device, read sound files through paw, and keep files beside the
 * device's state in the project.
 *
 * The functions of an attachment are called on the main thread of the
 * process that hosts the plugin, except where it says otherwise.
 *
 * The library exports one function, `paw_attachment_entry`.
 */
#ifndef PAW_ATTACH_H
#define PAW_ATTACH_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define PAW_ATTACH_ABI 1

/* Adds `size` bytes to an answer. */
typedef void (*paw_write_fn)(void *out, const uint8_t *data, size_t size);

/* What a sound file holds. paw decodes a file to two channels. */
typedef struct paw_audio_info {
    int64_t frames;
    double sample_rate;
    uint32_t channels;
} paw_audio_info;

/* What paw gives an attachment. */
typedef struct paw_attach_host {
    uint32_t abi;
    /* Open a sound file (WAV, AIFF, FLAC, MP3, Ogg Vorbis), decoded by paw.
     * NULL when paw cannot read it. Any thread. */
    void *(*audio_open)(const char *path, paw_audio_info *info);
    /* Read `frames` frames from frame `start` into one buffer for each of
     * `channel_count` channels. Frames outside the file read as silence.
     * Any thread, at the same time as other reads. */
    bool (*audio_read)(void *audio, int64_t start, int64_t frames, float *const *channels,
                       uint32_t channel_count);
    void (*audio_close)(void *audio);
} paw_attach_host;

/* What `call` answers. */
enum {
    /* The attachment does not know the method. */
    PAW_CALL_UNKNOWN = 0,
    /* Done; the answer is what was written. */
    PAW_CALL_DONE = 1,
    /* Failed; what was written says why. */
    PAW_CALL_FAILED = 2,
    /* Call again while the plugin is not active: paw holds the audio
     * thread off the plugin, deactivates it, calls again and activates it. */
    PAW_CALL_STOPPED = 3,
};

/* The methods that paw itself calls:
 *
 *   paw.clips       The audio clips of the device's part, as JSON (see
 *                   docs/reference/attachments.md). Only for an attachment
 *                   that answered PAW_CALL_DONE to the first one: paw calls it
 *                   again each time the clips or the tempo change.
 *   paw.file.save   The attachment's file for the project, or nothing. paw
 *                   keeps it beside the device's state as `<n>-<kind>.<name>`.
 *   paw.file.load   The file that paw kept, when paw makes the device again.
 *                   It comes before the first `paw.clips`.
 *   paw.busy        "1" while the plugin works on something that it shows
 *                   later (an analysis), else "0". The stepped engine of the
 *                   tests waits for it.
 */

typedef struct paw_attachment {
    uint32_t abi; /* PAW_ATTACH_ABI */
    /* A short name: the extension of the file the attachment keeps. */
    const char *name;
    /* Take a plugin, or return NULL to leave it alone. `format` is "clap";
     * `plugin` is the clap_plugin_t. */
    void *(*attach)(const paw_attach_host *host, const char *format, const void *plugin);
    /* A request for the device. */
    int (*call)(void *handle, const char *method, const uint8_t *data, size_t size, void *out,
                paw_write_fn write);
    /* The device is gone. paw destroys the plugin before or after. */
    void (*detach)(void *handle);
} paw_attachment;

typedef const paw_attachment *(*paw_attachment_entry_fn)(void);

#ifdef __cplusplus
}
#endif

#endif

//! TLS over the network, the client's side: it trusts an instance's
//! certificate the first time it sees it and holds it to that certificate
//! afterwards (as SSH does with a host key). The instance makes its own
//! certificate: see `paw_core::tls`. The connection itself is
//! `tokio-rustls`'s, on the client's runtime (`crate::runtime`).

use std::io;
use std::path::{Path, PathBuf};
use std::pin::Pin;
use std::sync::{Arc, Mutex, OnceLock};
use std::task::{Context, Poll};

use anyhow::{Context as _, Result, anyhow, bail};
use rustls::client::danger::{HandshakeSignatureValid, ServerCertVerified, ServerCertVerifier};
use rustls::crypto::CryptoProvider;
use rustls::pki_types::{CertificateDer, ServerName, UnixTime};
use rustls::{DigitallySignedStruct, SignatureScheme};
use tokio::io::{AsyncRead, AsyncWrite, ReadBuf};
use tokio::net::TcpStream;
use tokio::time::timeout;
use tokio_rustls::TlsConnector;
use tokio_rustls::client::TlsStream;

use crate::dirs::Dirs;
use crate::{HELLO_TIME, hex, sha256};

/// The cryptography everything here uses: ring's, which is pure Rust and
/// assembly, with no OpenSSL.
pub fn provider() -> Arc<CryptoProvider> {
    Arc::new(rustls::crypto::ring::default_provider())
}

/// How a certificate is named to a person: the SHA-256 of it, in
/// hexadecimal, in groups of four so that two can be compared by eye.
pub fn fingerprint(der: &[u8]) -> String {
    let digits = hex(&sha256(der));
    let groups: Vec<&str> = (0..digits.len()).step_by(4).map(|i| &digits[i..i + 4]).collect();
    groups.join(":")
}

/// What the client knows of the instances it has connected to: one line
/// each, the address as it was given and its certificate's fingerprint.
pub fn known_file(dirs: &Dirs) -> PathBuf {
    dirs.paw_state().join("known_instances")
}

/// [`known_file`] for the directories in the environment now. Only the
/// window (`paw-gui`, paused) calls it; a new caller uses [`known_file`]
/// with the directories of its program's start.
pub fn known_path() -> PathBuf {
    known_file(&Dirs::from_vars(|name| std::env::var_os(name)))
}

/// The fingerprint remembered for `address` in `file`.
pub fn known(file: &Path, address: &str) -> Option<String> {
    let text = std::fs::read_to_string(file).ok()?;
    text.lines().find_map(|line| {
        let (name, print) = line.split_once(' ')?;
        (name == address).then(|| print.trim().to_string())
    })
}

/// Remember `print` for `address` in `file`, in place of what was there.
pub fn remember(file: &Path, address: &str, print: &str) -> Result<()> {
    let text = std::fs::read_to_string(file).unwrap_or_default();
    let mut lines: Vec<String> = text
        .lines()
        .filter(|line| line.split_once(' ').is_none_or(|(name, _)| name != address))
        .map(str::to_string)
        .collect();
    lines.push(format!("{address} {print}"));
    if let Some(dir) = file.parent() {
        std::fs::create_dir_all(dir).with_context(|| format!("creating {}", dir.display()))?;
    }
    std::fs::write(file, lines.join("\n") + "\n").with_context(|| format!("writing {}", file.display()))
}

/// How a network connection is made.
#[derive(Clone, Debug)]
pub enum Wire {
    /// In TLS, holding the instance to the certificate remembered for its
    /// address in `known` (remembering it the first time).
    Tls {
        known: PathBuf,
        /// Take the certificate shown in place of one remembered that differs.
        accept_new: bool,
    },
    /// In the clear, for an instance started with `--no-tls`.
    Plain,
}

impl Wire {
    /// In TLS, holding each instance to the certificate remembered in the
    /// state directory of `dirs`.
    pub fn tls(dirs: &Dirs) -> Self {
        Wire::Tls {
            known: known_file(dirs),
            accept_new: false,
        }
    }
}

/// Accepts the certificate the instance shows as long as it is the one
/// remembered (or none is), and checks the handshake is signed with it.
#[derive(Debug)]
struct Pinned {
    expected: Option<String>,
    accept_new: bool,
    shown: Mutex<Option<String>>,
    provider: Arc<CryptoProvider>,
}

impl ServerCertVerifier for Pinned {
    fn verify_server_cert(
        &self,
        end_entity: &CertificateDer<'_>,
        _intermediates: &[CertificateDer<'_>],
        _server_name: &ServerName<'_>,
        _ocsp: &[u8],
        _now: UnixTime,
    ) -> Result<ServerCertVerified, rustls::Error> {
        let print = fingerprint(end_entity);
        *self.shown.lock().unwrap() = Some(print.clone());
        match &self.expected {
            Some(expected) if *expected != print && !self.accept_new => {
                Err(rustls::Error::General("not the certificate remembered".into()))
            }
            _ => Ok(ServerCertVerified::assertion()),
        }
    }

    fn verify_tls12_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, rustls::Error> {
        rustls::crypto::verify_tls12_signature(
            message,
            cert,
            dss,
            &self.provider.signature_verification_algorithms,
        )
    }

    fn verify_tls13_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, rustls::Error> {
        rustls::crypto::verify_tls13_signature(
            message,
            cert,
            dss,
            &self.provider.signature_verification_algorithms,
        )
    }

    fn supported_verify_schemes(&self) -> Vec<SignatureScheme> {
        self.provider.signature_verification_algorithms.supported_schemes()
    }
}

/// The socket under a TLS connection, noting the first byte the other side
/// sends: an instance that speaks first in the clear (`{`) is one without
/// TLS.
pub(crate) struct Sniff {
    socket: TcpStream,
    first: Arc<OnceLock<u8>>,
}

impl AsyncRead for Sniff {
    fn poll_read(mut self: Pin<&mut Self>, cx: &mut Context<'_>, buf: &mut ReadBuf<'_>) -> Poll<io::Result<()>> {
        let before = buf.filled().len();
        let polled = Pin::new(&mut self.socket).poll_read(cx, buf);
        if self.first.get().is_none()
            && let Some(&byte) = buf.filled().get(before)
        {
            let _ = self.first.set(byte);
        }
        polled
    }
}

impl AsyncWrite for Sniff {
    fn poll_write(mut self: Pin<&mut Self>, cx: &mut Context<'_>, data: &[u8]) -> Poll<io::Result<usize>> {
        Pin::new(&mut self.socket).poll_write(cx, data)
    }

    fn poll_write_vectored(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        data: &[io::IoSlice<'_>],
    ) -> Poll<io::Result<usize>> {
        Pin::new(&mut self.socket).poll_write_vectored(cx, data)
    }

    fn is_write_vectored(&self) -> bool {
        self.socket.is_write_vectored()
    }

    fn poll_flush(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<io::Result<()>> {
        Pin::new(&mut self.socket).poll_flush(cx)
    }

    fn poll_shutdown(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<io::Result<()>> {
        Pin::new(&mut self.socket).poll_shutdown(cx)
    }
}

/// What came of connecting in TLS: the connection, and the certificate's
/// fingerprint when it was remembered for the first time (or again, in
/// place of another).
pub(crate) struct Opened {
    pub stream: TlsStream<Sniff>,
    pub trusted_now: Option<String>,
}

/// Make a TLS connection over `socket` to the instance at `address`,
/// holding it to the certificate remembered in `known_file`. The handshake
/// may take [`HELLO_TIME`]; afterwards, reading waits as long as the kernel
/// is quiet.
pub(crate) async fn connect(address: &str, socket: TcpStream, known_file: &Path, accept_new: bool) -> Result<Opened> {
    let provider = provider();
    let expected = known(known_file, address);
    let pinned = Arc::new(Pinned {
        expected: expected.clone(),
        accept_new,
        shown: Mutex::new(None),
        provider: provider.clone(),
    });
    let config = rustls::ClientConfig::builder_with_provider(provider)
        .with_safe_default_protocol_versions()?
        .dangerous()
        .with_custom_certificate_verifier(pinned.clone())
        .with_no_client_auth();
    // The name is not checked (the certificate is held to its fingerprint
    // instead), but TLS wants one.
    let host = address.rsplit_once(':').map_or(address, |(host, _)| host);
    let host = host.trim_start_matches('[').trim_end_matches(']');
    let name = ServerName::try_from(host.to_string())
        .or_else(|_| ServerName::try_from("paw-instance".to_string()))
        .map_err(|err| anyhow!("{err}"))?;
    let first = Arc::new(OnceLock::new());
    let sniff = Sniff {
        socket,
        first: first.clone(),
    };
    let handshake = TlsConnector::from(Arc::new(config)).connect(name, sniff);
    let handshake = match timeout(HELLO_TIME, handshake).await {
        Ok(done) => done,
        Err(_) => Err(io::Error::new(io::ErrorKind::TimedOut, "the handshake took too long")),
    };
    let stream = match handshake {
        Ok(stream) => stream,
        Err(err) => {
            let shown = pinned.shown.lock().unwrap().clone();
            if let (Some(expected), Some(shown)) = (&expected, &shown)
                && expected != shown
            {
                bail!(
                    "the instance at {address} shows another certificate than the one remembered:\n  \
                     remembered: {expected}\n  shown now:  {shown}\n\
                     If the instance made a new one (its state directory was lost, or it moved \
                     machine), check the fingerprint it prints when it starts and connect again \
                     with --accept-certificate. Otherwise something between here and there is \
                     pretending to be it. (Remembered in {}.)",
                    known_file.display()
                );
            }
            if first.get() == Some(&b'{') {
                bail!(
                    "the instance at {address} speaks without encryption: it is older than this \
                     program, or was started with --no-tls. Connect with --no-tls if the network \
                     is one you trust."
                );
            }
            return Err(anyhow!(err).context(format!("no TLS with the instance at {address}")));
        }
    };
    let shown = pinned.shown.lock().unwrap().clone().context("the instance showed no certificate")?;
    let trusted_now = if expected.as_deref() != Some(shown.as_str()) {
        remember(known_file, address, &shown)?;
        Some(shown)
    } else {
        None
    };
    Ok(Opened { stream, trusted_now })
}


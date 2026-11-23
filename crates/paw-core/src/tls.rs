//! The instance's side of TLS: the certificate it shows to whoever
//! connects over the network. It is made the first time the instance
//! listens on TCP and kept in the state directory, so that clients, which
//! remember it the first time they see it (`paw_proto::tls`), see the
//! same one every time.

use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::Arc;

use anyhow::{Context, Result};
use rustls::pki_types::{CertificateDer, PrivateKeyDer, PrivatePkcs8KeyDer};

pub(crate) use paw_proto::tls::fingerprint;

/// Where the certificate and its key are kept: `$XDG_STATE_HOME/paw/tls`.
pub fn default_dir(dirs: &paw_proto::dirs::Dirs) -> PathBuf {
    dirs.paw_state().join("tls")
}

/// The instance's certificate and private key, from `dir`, made and written
/// there (the key readable by its owner alone) if there are none yet.
fn load_or_make(dir: &Path) -> Result<(Vec<u8>, Vec<u8>)> {
    let (cert_path, key_path) = (dir.join("cert.der"), dir.join("key.der"));
    if let (Ok(cert), Ok(key)) = (std::fs::read(&cert_path), std::fs::read(&key_path))
        && !cert.is_empty()
        && !key.is_empty()
    {
        return Ok((cert, key));
    }
    std::fs::create_dir_all(dir).with_context(|| format!("creating {}", dir.display()))?;
    let made = rcgen::generate_simple_self_signed(vec!["paw-instance".to_string()])
        .context("making a certificate")?;
    let (cert, key) = (made.cert.der().to_vec(), made.signing_key.serialize_der());
    use std::os::unix::fs::OpenOptionsExt;
    let mut file = std::fs::OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .mode(0o600)
        .open(&key_path)
        .with_context(|| format!("writing {}", key_path.display()))?;
    file.write_all(&key)?;
    std::fs::write(&cert_path, &cert).with_context(|| format!("writing {}", cert_path.display()))?;
    Ok((cert, key))
}

/// What a listening instance needs for TLS: its configuration, and the
/// fingerprint of its certificate to tell people, who can compare it with
/// what their clients remember.
pub struct Identity {
    pub config: Arc<rustls::ServerConfig>,
    pub fingerprint: String,
}

/// The instance's TLS configuration, with the certificate kept in `dir`.
pub fn identity(dir: &Path) -> Result<Identity> {
    let (cert, key) = load_or_make(dir)?;
    let fingerprint = fingerprint(&cert);
    let mut config = rustls::ServerConfig::builder_with_provider(paw_proto::tls::provider())
        .with_safe_default_protocol_versions()?
        .with_no_client_auth()
        .with_single_cert(
            vec![CertificateDer::from(cert)],
            PrivateKeyDer::Pkcs8(PrivatePkcs8KeyDer::from(key)),
        )
        .with_context(|| format!("the certificate in {} does not go with its key", dir.display()))?;
    // Clients do not come back for a shorter handshake; tickets would only
    // be more to send.
    config.send_tls13_tickets = 0;
    Ok(Identity {
        config: Arc::new(config),
        fingerprint,
    })
}

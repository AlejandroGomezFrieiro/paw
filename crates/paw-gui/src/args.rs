//! The command line of `paw-gui`, in clap's derive form. The options of the
//! window are here; every other argument goes on to the kernel untouched.

use std::path::PathBuf;

use clap::{Parser, ValueEnum};

/// How the window is drawn: OpenGL on whatever driver the system has, or
/// asked of Mesa's processor driver.
#[derive(Clone, Copy, Debug, PartialEq, ValueEnum)]
pub enum Renderer {
    /// OpenGL on the graphics card (the default)
    Gpu,
    /// Mesa draws on the processor (llvmpipe)
    Software,
}

/// paw-gui: a graphical frontend for paw
///
/// Without --socket or --connect it starts a kernel and shows it. The other
/// arguments are passed on to `paw --headless`; see `paw --help`.
#[derive(Parser, Debug)]
#[command(name = "paw-gui", version, override_usage = "paw-gui [OPTIONS] [KERNEL ARGS]...")]
pub struct Cli {
    /// Show a kernel that is already running, on its socket
    #[arg(long, value_name = "PATH")]
    pub socket: Option<PathBuf>,
    /// Show a kernel on another machine (started with --listen-tcp)
    #[arg(long, value_name = "HOST:PORT")]
    pub connect: Option<String>,
    /// The token for --connect (also $PAW_TOKEN)
    #[arg(long, value_name = "TOKEN")]
    pub token: Option<String>,
    /// The file that holds the token for --connect
    #[arg(long, value_name = "PATH")]
    pub token_file: Option<PathBuf>,
    /// Take the certificate it shows though another was remembered for it
    #[arg(long)]
    pub accept_certificate: bool,
    /// Connect in the clear, to a kernel started with --no-tls
    #[arg(long)]
    pub no_tls: bool,
    /// Play its sound here (about 1 Mbit/s); also in the engine menu
    #[arg(long)]
    pub listen_audio: bool,
    /// Draw with OpenGL on the graphics card (gpu, the default) or have Mesa
    /// draw on the processor (software, llvmpipe); also PAW_GUI_RENDERER
    #[arg(long, value_enum, value_name = "RENDERER")]
    pub renderer: Option<Renderer>,
    /// Kernel options and the project, passed on to `paw --headless`
    #[arg(num_args = 0.., allow_hyphen_values = true, trailing_var_arg = true, value_name = "KERNEL ARGS")]
    pub rest: Vec<String>,
}

/// The renderer asked for with `--renderer`, else by `env`
/// (`PAW_GUI_RENDERER`); else the GPU.
pub fn renderer_choice(option: Option<Renderer>, env: Option<&str>) -> anyhow::Result<Renderer> {
    if let Some(renderer) = option {
        return Ok(renderer);
    }
    match env.filter(|name| !name.is_empty()) {
        None | Some("gpu") => Ok(Renderer::Gpu),
        Some("software") => Ok(Renderer::Software),
        Some(other) => anyhow::bail!("the renderer is gpu or software, not {other}"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn parse(args: &[&str]) -> Result<Cli, clap::Error> {
        Cli::try_parse_from(std::iter::once("paw-gui").chain(args.iter().copied()))
    }

    #[test]
    fn the_renderer_is_chosen_by_option_then_environment() {
        let cli = parse(&["--renderer", "software", "song.json"]).unwrap();
        assert_eq!(renderer_choice(cli.renderer, Some("gpu")).unwrap(), Renderer::Software);
        assert_eq!(cli.rest, ["song.json"], "the option is not passed on to the kernel");
        assert_eq!(renderer_choice(None, Some("software")).unwrap(), Renderer::Software);
        assert_eq!(renderer_choice(None, None).unwrap(), Renderer::Gpu);
        assert_eq!(renderer_choice(None, Some("")).unwrap(), Renderer::Gpu);
        assert!(renderer_choice(None, Some("vulkan")).is_err());
        assert!(parse(&["--renderer"]).is_err());
        assert!(parse(&["--renderer", "vulkan"]).is_err());
    }

    #[test]
    fn the_kernels_arguments_pass_through_untouched() {
        let cli = parse(&["--socket", "/s", "--audio", "null", "-e", "x=1", "--clean", "song"]).unwrap();
        assert_eq!(cli.socket, Some("/s".into()));
        assert_eq!(cli.rest, ["--audio", "null", "-e", "x=1", "--clean", "song"]);
        let cli = parse(&["--clean", "--renderer", "gpu", "--keys", "jj"]).unwrap();
        assert_eq!(cli.rest, ["--clean", "--renderer", "gpu", "--keys", "jj"], "after the first kernel argument, all pass");
    }
}

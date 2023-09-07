mod eww;
use std::env;

#[tokio::main]
async fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        return;
    }
    match (&args[1]).as_str() {
        "daemon" => {
            let _ = eww::dispatcher(&args[2]).await;
        }
        _ => {println!("Unknown subcommand!")}
    }
}

pub(crate) mod mainbar;

pub async fn dispatcher(kw: &str) {
    match kw {
        "mainbar" => {
            let _ = mainbar::main().await;
        }
        _ => {println!("Unknows daemon arg!")}
    }
}

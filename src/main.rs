use watermark_remover_mcp_server::run_main;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    run_main().await?;
    Ok(())
}

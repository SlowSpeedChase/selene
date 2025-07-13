"""
Main entry point for Selene - Second Brain Processing System
"""

import typer
from loguru import logger
from rich.console import Console

from selene import __version__

app = typer.Typer(
    name="selene",
    help="Selene - Second Brain Processing System",
    add_completion=False,
)
console = Console()


def setup_logging() -> None:
    """Configure logging for the application."""
    logger.remove()
    logger.add(
        "logs/selene.log",
        rotation="1 day",
        retention="30 days",
        level="INFO",
        format="{time:YYYY-MM-DD HH:mm:ss} | {level} | {name}:{function}:{line} | {message}",
    )
    logger.add(
        lambda msg: console.print(msg, end=""),
        level="INFO",
        format="<green>{time:HH:mm:ss}</green> | <level>{level}</level> | {message}",
    )


@app.command()
def start() -> None:
    """Start the Selene system."""
    setup_logging()
    logger.info("System started")
    console.print(f"[bold green]Selene v{__version__} - Second Brain Processing System[/bold green]")
    console.print("[cyan]System initialized successfully![/cyan]")


@app.command()
def version() -> None:
    """Show version information."""
    console.print(f"Selene version: {__version__}")


if __name__ == "__main__":
    app()
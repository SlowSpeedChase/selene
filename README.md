# Selene - Second Brain Processing System

A modern Python application for processing and managing notes using LLMs, vector databases, and intelligent file monitoring.

## Features

- **AI-Powered Note Processing**: Leverage Large Language Models for content analysis and enhancement
- **Vector Database Integration**: Efficient semantic search and similarity matching using ChromaDB
- **Intelligent File Monitoring**: Real-time file system watching with automated processing
- **Modern Python Architecture**: Built with type hints, async support, and best practices
- **Rich CLI Interface**: Beautiful command-line interface with progress indicators and logging

## Quick Start

### Prerequisites

- Python 3.9 or higher
- pip (Python package manager)

### Installation

1. **Clone the repository**:
   ```bash
   git clone <repository-url>
   cd selene
   ```

2. **Create and activate a virtual environment**:
   ```bash
   # Create virtual environment
   python -m venv venv
   
   # Activate virtual environment
   # On macOS/Linux:
   source venv/bin/activate
   # On Windows:
   venv\Scripts\activate
   ```

3. **Install dependencies**:
   ```bash
   # Install core dependencies
   pip install -r requirements.txt
   
   # For development (includes testing and linting tools)
   pip install -r requirements-dev.txt
   
   # Or install in development mode with optional dependencies
   pip install -e ".[dev]"
   ```

4. **Set up environment variables** (optional):
   ```bash
   cp .env.example .env
   # Edit .env with your API keys and configuration
   ```

### Usage

**Start the system**:
```bash
# Using the installed command
selene start

# Or run directly
python -m selene.main start
```

**Check version**:
```bash
selene version
```

**Get help**:
```bash
selene --help
```

## Development

### Project Structure

```
selene/
├── selene/                 # Main package
│   ├── __init__.py        # Package initialization
│   └── main.py            # CLI entry point
├── tests/                 # Test suite
│   ├── __init__.py
│   └── test_main.py       # Main module tests
├── docs/                  # Documentation
├── scripts/               # Utility scripts
├── logs/                  # Application logs
├── requirements.txt       # Core dependencies
├── requirements-dev.txt   # Development dependencies
├── pyproject.toml         # Project configuration
├── pytest.ini            # Test configuration
└── README.md              # This file
```

### Running Tests

```bash
# Run all tests
pytest

# Run with coverage
pytest --cov=selene

# Run specific test file
pytest tests/test_main.py
```

### Code Quality

The project uses several tools to maintain code quality:

```bash
# Format code
black selene tests

# Sort imports
isort selene tests

# Lint code
flake8 selene tests

# Type checking
mypy selene
```

### Pre-commit Hooks

Install pre-commit hooks to automatically run quality checks:

```bash
pre-commit install
```

## Configuration

### Environment Variables

Create a `.env` file in the project root:

```bash
# OpenAI Configuration
OPENAI_API_KEY=your_openai_api_key_here

# ChromaDB Configuration
CHROMA_DB_PATH=./chroma_db

# Logging Configuration
LOG_LEVEL=INFO
LOG_FILE=logs/selene.log

# File Monitoring
WATCH_DIRECTORIES=./data,./notes
```

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Run tests and quality checks
5. Commit your changes (`git commit -m 'Add amazing feature'`)
6. Push to the branch (`git push origin feature/amazing-feature`)
7. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Roadmap

- [ ] Core note processing pipeline
- [ ] Vector database integration
- [ ] File monitoring system
- [ ] Web interface
- [ ] Plugin system
- [ ] Advanced AI features

## Support

For questions, issues, or contributions, please open an issue on GitHub.
# Aura Mobile - Private Offline AI Assistant

Aura Mobile is a privacy-first, fully offline AI assistant powered by on-device LLMs. It features a sophisticated "SuperGravity" architecture that enables long-term memory, document analysis (RAG), and voice interaction without ever sending data to the cloud.

## Key Features

### 🧠 True Offline Intelligence
- **On-Device LLMs**: Runs powerful AI models (like TinyLlama, Qwen, Phi) directly on your phone.
- **Privacy First**: Your data, chat history, and documents never leave your device.
- **Works Anywhere**: No internet connection required for core functionality.

### 💾 Long-Term Memory
- **"Remember This"**: Tell Aura to remember facts, appointments, or ideas.
- **Automatic Retrieval**: Aura automatically recalls relevant information during conversations.
- **Smart Reminders**: "Remember I have a meeting at 2pm" automatically schedules a local notification.

### 📄 Document Intelligence (RAG)
- **Chat with PDFs**: Upload documents and ask questions about them.
- **Summarization**: Instantly summarize long articles or reports.
- **Contextual Answers**: Aura cites information directly from your files.

### 🎙️ Voice Interaction
- **Hands-Free Mode**: Talk to Aura and hear responses via Text-to-Speech.
- **Natural Conversation**: Fluid voice-to-voice interaction pipeline.

### ⚡ SuperGravity Architecture
- **Orchestrator Pipeline**: Advanced message processing (Intent -> Route -> Context -> LLM).
- **Rule-Based Intent**: Fast, accurate detection of user needs without wasting LLM resources.
- **Optimized Performance**: Strict context management for smooth operation on mobile hardware.

## Getting Started

1.  **Download a Model**: On first launch, download a supported GGUF model.
2.  **Start Chatting**: Type or speak to interact.
3.  **Try Memory**: "Save that my door code is 1234." -> "What is my door code?"
4.  **Try RAG**: Tap the attachment icon to upload a PDF.

## Development

This project uses Flutter with Riverpod for state management and `llama.cpp` for inference.

- **Architecture**: Clean Architecture + SuperGravity Pipeline
- **Local Database**: SQLite for memories and document chunks
- **Vector Store**: Local embedding comparison for RAG

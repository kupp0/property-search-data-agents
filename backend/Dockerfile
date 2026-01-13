# Use official Python runtime as a parent image
# python:3.11-slim is a lightweight image that includes only the minimal packages needed to run Python.
FROM python:3.11-slim

# Ensure python output is sent directly to terminal (no buffering)
ENV PYTHONUNBUFFERED=1

# Set the working directory in the container
WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    python3-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy the requirements file into the container at /app
COPY requirements.txt .

# Install any needed packages specified in requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

# Copy the current directory contents into the container at /app
COPY . .

# Make port 8080 available to the world outside this container
EXPOSE 8080

# Define environment variable
ENV PORT=8080

# Run uvicorn when the container launches
# Uvicorn is an ASGI web server implementation for Python.
# We bind to 0.0.0.0 to ensure the container listens on all network interfaces, which is required for Cloud Run.
CMD ["sh", "-c", "uvicorn main:app --host 0.0.0.0 --port ${PORT}"]

FROM us-central1-docker.pkg.dev/database-toolbox/toolbox/toolbox:latest

WORKDIR /app

# Copy the tools configuration
COPY tools.yaml /secrets/tools.yaml

# Expose the port
EXPOSE 8080

# Run the toolbox
# We use port 8080 for Cloud Run
ENTRYPOINT ["/toolbox", "--tools-file=/secrets/tools.yaml", "--address=0.0.0.0", "--port=8080"]

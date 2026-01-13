# Build Stage
FROM node:20-alpine as build

WORKDIR /app

COPY package.json ./
RUN npm install

COPY . .
RUN npm run build

# Runtime Stage
FROM nginx:alpine

# Copy build artifacts
COPY --from=build /app/dist /usr/share/nginx/html

# Copy custom configuration
COPY nginx.conf.template /etc/nginx/templates/default.conf.template
COPY entrypoint.sh /docker-entrypoint.d/99-custom-entrypoint.sh

# Make entrypoint executable
RUN chmod +x /docker-entrypoint.d/99-custom-entrypoint.sh

EXPOSE 8080

# Nginx image automatically runs entrypoint scripts in /docker-entrypoint.d/
# and then starts nginx.

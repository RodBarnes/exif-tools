# Run import
docker run -it \
  -v /home/rod/tmp/immich:/import:ro \
  -e IMMICH_INSTANCE_URL=http://192.168.0.19:2283/api \
  -e IMMICH_API_KEY=$KEY \
  ghcr.io/immich-app/immich-cli:latest \
  upload --recursive /import

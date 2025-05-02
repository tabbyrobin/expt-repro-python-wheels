sudo docker build -t uv_build_repro .
mkdir -p OUTPUT
sudo docker run -it \
  -v ./uv_build_repro.sh:/usr/local/bin/uv_build_repro.sh:ro \
  -v ./OUTPUT:/opt/OUTPUT:rw \
  -w /opt/OUTPUT \
  uv_build_repro

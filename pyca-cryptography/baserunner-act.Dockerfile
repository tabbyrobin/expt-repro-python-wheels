FROM catthehacker/ubuntu:js-latest
# curl https://raw.githubusercontent.com/catthehacker/docker_images/refs/heads/master/linux/ubuntu/scripts/rust.sh
RUN git clone https://github.com/catthehacker/docker_images && \
    prior_dir="$(pwd)" && cd docker_images/linux/ubuntu/scripts && \
    bash rust.sh && \
    cd "$prior_dir" && rm -rf docker_images
#RUN . /etc/environment
ENV PATH="/usr/share/rust/.rustup/bin:/usr/share/rust/.cargo/bin:$PATH"
RUN cargo -V

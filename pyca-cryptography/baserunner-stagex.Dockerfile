FROM stagex/core-filesystem
COPY --from=stagex/core-nodejs . /
COPY --from=stagex/core-coreutils . /
COPY --from=stagex/core-git . /
COPY --from=stagex/user-py-setuptools-rust . /
# RUN [ ! -z $GITHUB_ACTIONS ]
# then
#      echo "MY_VAR='myValue'" >> $GITHUB_ENV
#      https://plzm.blog/202203-env-vars

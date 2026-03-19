FROM alpine

RUN apk add --no-cache curl jq

# Pin version to 0.4.21 until this (https://github.com/superfly/flyctl/pull/4783) is merged
RUN curl -L https://fly.io/install.sh | FLYCTL_INSTALL=/usr/local sh -s -- v0.4.21

COPY entrypoint.sh /entrypoint.sh

# Ensure fly doesn't automatically update (remove along with v0.4.21 pin).
ENV FLY_NO_UPDATE_CHECK=1

ENTRYPOINT ["/entrypoint.sh"]

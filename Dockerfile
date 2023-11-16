FROM golang:1.21-alpine AS builder

RUN mkdir -p /app/bin
WORKDIR /src
COPY . .
ENV CGO_ENABLED=0
RUN apk -U add nodejs yarn && \
    yarn install && \
    yarn build:css && \
    go build -o /app/bin/daq .

FROM scratch
COPY --from=builder /app/bin/daq /daq

CMD ["/daq"]
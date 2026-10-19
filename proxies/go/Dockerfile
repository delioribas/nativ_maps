# nativ_maps reference proxy, Go version.
#
#   docker build -t nativ-maps-proxy-go .
#   docker run -p 8080:8080 -e PROXY_TOKEN=… -e AWS_REGION=us-east-1 \
#     -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY nativ-maps-proxy-go

FROM golang:1.24-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /proxy .

# Static, no shell, runs as an unprivileged user, and ships the CA
# certificates the HTTPS calls to AWS need.
FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /proxy /proxy
ENV PORT=8080
EXPOSE 8080
ENTRYPOINT ["/proxy"]

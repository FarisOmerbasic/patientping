FROM golang:1.27.1-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/ ./cmd/...

FROM gcr.io/distroless/static-debian13:nonroot
COPY --from=build /out/api /api
COPY --from=build /out/worker /worker
# distroless's nonroot user, as a number so Kubernetes (runAsNonRoot) can check it isn't root
USER 65532
EXPOSE 8080
CMD ["/api"]

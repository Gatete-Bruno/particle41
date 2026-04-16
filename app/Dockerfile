FROM golang:1.24-alpine AS builder

WORKDIR /app
COPY go.mod ./
COPY main.go ./
RUN go build -o simpletimeservice .

FROM scratch

COPY --from=builder /app/simpletimeservice /simpletimeservice

USER 65534

EXPOSE 8080

ENTRYPOINT ["/simpletimeservice"]

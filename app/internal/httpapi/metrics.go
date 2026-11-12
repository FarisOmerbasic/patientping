package httpapi

import (
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
)

// The API's two metrics. promauto registers them in the default registry,
// which promhttp.Handler() shows on /metrics.
var (
	// A counter only goes up: one more for every answered request.
	requestsTotal = promauto.NewCounterVec(prometheus.CounterOpts{
		Name: "http_requests_total",
		Help: "Requests the API answered, by route, method and status code.",
	}, []string{"route", "method", "code"})

	// A histogram counts each answer time into buckets (up to 5 ms, 10 ms,
	// ... 10 s), so Prometheus can work out percentiles like p95 later.
	requestDuration = promauto.NewHistogramVec(prometheus.HistogramOpts{
		Name:    "http_request_duration_seconds",
		Help:    "How long the API took to answer, by route.",
		Buckets: prometheus.DefBuckets,
	}, []string{"route"})
)

// instrument counts and times every request that next answers.
//
// The route label is the pattern that matched, like /api/patients, never the
// path the client sent. Every new label value makes a new time series in
// Prometheus, so a label may only take values from a short, fixed list:
// a scanner that tries a thousand random paths must not add a thousand series.
func instrument(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rec := &statusRecorder{ResponseWriter: w, code: http.StatusOK}

		next.ServeHTTP(rec, r)

		// By now the mux has set r.Pattern, for example "GET /api/patients".
		// A request that matched no route (404, 405) has an empty pattern.
		method, route, found := strings.Cut(r.Pattern, " ")
		if !found {
			method, route = "none", "none"
		}
		requestsTotal.WithLabelValues(route, method, strconv.Itoa(rec.code)).Inc()
		requestDuration.WithLabelValues(route).Observe(time.Since(start).Seconds())
	})
}

// statusRecorder remembers the status code a handler sends. A handler that
// never calls WriteHeader sends 200.
type statusRecorder struct {
	http.ResponseWriter
	code int
}

func (s *statusRecorder) WriteHeader(code int) {
	s.code = code
	s.ResponseWriter.WriteHeader(code)
}

// Unwrap lets http.ResponseController reach the ResponseWriter underneath.
func (s *statusRecorder) Unwrap() http.ResponseWriter { return s.ResponseWriter }

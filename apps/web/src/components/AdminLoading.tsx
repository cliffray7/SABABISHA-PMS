export function RefreshingIndicator({ label = "Refreshing page" }: { label?: string }) {
  return <div className="admin-refresh-indicator" role="status" aria-label={label} aria-live="polite">
    <span className="admin-refresh-indicator-track" aria-hidden="true"><i/></span>
    <span className="admin-loading-sr">{label}</span>
  </div>;
}

export function MetricGridLoading({ count = 6 }: { count?: number }) {
  return <div className="admin-loading-metrics" role="status" aria-label="Loading platform metrics" aria-busy="true">
    {Array.from({ length: count }, (_, index) => <div className="admin-loading-metric" key={index} aria-hidden="true"><i/><b/><small/></div>)}
    <span className="admin-loading-sr">Loading platform metrics</span>
  </div>;
}

export function AnalyticsPageLoading() {
  return <div className="admin-loading-analytics" role="status" aria-label="Loading analytics" aria-busy="true">
    <span className="admin-loading-status"><i/>Loading analytics</span>
    <div className="admin-loading-summary">{Array.from({ length: 4 }, (_, index) => <div className="admin-loading-stat" key={index} aria-hidden="true"><i/><b/><small/></div>)}</div>
    <div className="admin-loading-charts">{Array.from({ length: 4 }, (_, index) => <div className="admin-loading-chart" key={index} aria-hidden="true"><span/><span/><span/><span/></div>)}</div>
    <span className="admin-loading-sr">Loading analytics data</span>
  </div>;
}

export function ManagementTableLoading({ label }: { label: string }) {
  return <div className="admin-loading-table" role="status" aria-label={`Loading ${label}`} aria-busy="true">
    <div className="admin-loading-table-head" aria-hidden="true"><i/><i/><i/><i/></div>
    {Array.from({ length: 5 }, (_, index) => <div className="admin-loading-table-row" key={index} aria-hidden="true"><i/><i/><i/><i/></div>)}
    <span className="admin-loading-sr">Loading {label}</span>
  </div>;
}

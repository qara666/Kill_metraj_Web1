/**
 * OSRMService — Public OSRM routing (router.project-osrm.org)
 * Uses the same API call as /map tab for consistency and speed.
 * Direct browser fetch — no backend proxy needed (CORS is open on public OSRM).
 */

export interface OSRMRouteResult {
  feasible: boolean
  totalDuration?: number
  totalDistance?: number
  geometry?: string
  legs?: any[]
}

const OSRM_BASE_URL = 'https://router.project-osrm.org'

export class OSRMService {
  /**
   * Calculate route using public OSRM trip API — identical to /map tab.
   * Uses trip/v1 (TSP) for optimal ordering, with route/v1 fallback.
   */
  static async calculateRoute(
    locations: { lat: number; lng: number }[]
  ): Promise<OSRMRouteResult> {
    if (locations.length < 2) return { feasible: false }

    const coordsStr = locations.map(l => `${Number(l.lng).toFixed(7)},${Number(l.lat).toFixed(7)}`).join(';')

    // Primary: trip/v1 (same as /map tab — gives optimal route order)
    try {
      const tripUrl = `${OSRM_BASE_URL}/trip/v1/driving/${coordsStr}?source=first&overview=full&geometries=geojson`
      const r = await fetch(tripUrl, { signal: AbortSignal.timeout(8000) })
      if (r.ok) {
        const d = await r.json()
        if (d.code === 'Ok' && d.trips?.[0]) {
          return {
            feasible: true,
            totalDistance: d.trips[0].distance,
            totalDuration: d.trips[0].duration
          }
        }
      }
    } catch { }

    // Fallback: route/v1
    try {
      const routeUrl = `${OSRM_BASE_URL}/route/v1/driving/${coordsStr}?overview=false&steps=false`
      const r = await fetch(routeUrl, { signal: AbortSignal.timeout(8000) })
      if (!r.ok) return { feasible: false }
      const d = await r.json()
      if (d.code !== 'Ok' || !d.routes?.[0]) return { feasible: false }
      return {
        feasible: true,
        totalDistance: d.routes[0].distance,
        totalDuration: d.routes[0].duration
      }
    } catch (error: any) {
      console.warn('[OSRM] Error:', error?.message ?? error)
      return { feasible: false }
    }
  }
}

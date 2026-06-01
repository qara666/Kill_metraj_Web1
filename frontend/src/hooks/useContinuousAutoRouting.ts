import { useEffect, useRef } from 'react';
import { useExcelData } from '../contexts/ExcelDataContext';
import { groupAllOrdersByTimeWindow } from '../utils/route/routeCalculationHelpers';
import { robustGeocodingService } from '../services/robust-geocoding/RobustGeocodingService';
import { localStorageUtils } from '../utils/ui/localStorage';
import { toast } from 'react-hot-toast';
import { normalizeCourierName, getCourierName } from '../utils/data/courierName';
import { useDashboardStore } from '../stores/useDashboardStore';
import { getStableOrderId } from '../utils/data/orderId';
import { needsAddressClarification } from '../utils/data/addressUtils';
import { calculateDistance } from '../utils/geoUtils';
import { useRouteCalculationStore } from '../stores/useRouteCalculationStore';
import { API_URL } from '../config/apiConfig';
import { haversineDistance } from '../utils/routes/routeOptimizationHelpers';

// ─── Inline OSRM race — same logic as /map tab ─────────────────────────────
type RaceResult = { dist: number; dur: number; eng: string; geometry?: string };

async function turboRouteRace(
    routePoints: { lat: number; lng: number }[],
    yapikoBaseUrl?: string
): Promise<RaceResult> {
    const coordsStr = routePoints.map(p => `${p.lng.toFixed(7)},${p.lat.toFixed(7)}`).join(';');
    const engines: Promise<RaceResult>[] = [];

    // Engine 1: Yapiko private OSRM — trip (TSP optimal order)
    if (yapikoBaseUrl) {
        const base = yapikoBaseUrl.trim().replace(/\/+$/, '');
        engines.push((async (): Promise<RaceResult> => {
            const url = `${base}/trip/v1/driving/${coordsStr}?source=first&overview=full&geometries=polyline`;
            const r = await fetch(url, { signal: AbortSignal.timeout(5000) });
            const d = await r.json();
            if (d.code !== 'Ok' || !d.trips?.[0]) throw new Error('no_trip');
            return { dist: d.trips[0].distance, dur: d.trips[0].duration, eng: 'yapiko_trip', geometry: d.trips[0].geometry };
        })());
        // Also try standard route as parallel bet
        engines.push((async (): Promise<RaceResult> => {
            const url = `${base}/route/v1/driving/${coordsStr}?overview=full&geometries=polyline`;
            const r = await fetch(url, { signal: AbortSignal.timeout(5000) });
            const d = await r.json();
            if (d.code !== 'Ok' || !d.routes?.[0]) throw new Error('no_route');
            return { dist: d.routes[0].distance, dur: d.routes[0].duration, eng: 'yapiko_route', geometry: d.routes[0].geometry };
        })());
    }

    // Engine 2: Public OSRM — EXACTLY what /map tab uses (router.project-osrm.org)
    engines.push((async (): Promise<RaceResult> => {
        const url = `https://router.project-osrm.org/trip/v1/driving/${coordsStr}?source=first&overview=full&geometries=geojson`;
        const r = await fetch(url, { signal: AbortSignal.timeout(8000) });
        const d = await r.json();
        if (d.code !== 'Ok' || !d.trips?.[0]) throw new Error('no_pub_trip');
        return { dist: d.trips[0].distance, dur: d.trips[0].duration, eng: 'osrm_public_trip' };
    })());

    // Safety net: Haversine ×1.3 fires after 200ms — ZERO downtime guarantee
    engines.push(new Promise<RaceResult>(resolve =>
        setTimeout(() => {
            let ckm = 0;
            for (let i = 0; i < routePoints.length - 1; i++)
                ckm += calculateDistance(routePoints[i], routePoints[i + 1]) / 1000;
            resolve({ dist: ckm * 1.3 * 1000, dur: ckm * 2 * 60, eng: 'haversine_1.3x' });
        }, 200)
    ));

    try {
        return await Promise.any(engines);
    } catch {
        let ckm = 0;
        for (let i = 0; i < routePoints.length - 1; i++)
            ckm += calculateDistance(routePoints[i], routePoints[i + 1]) / 1000;
        return { dist: ckm * 1.4 * 1000, dur: ckm * 2 * 60, eng: 'haversine_fallback' };
    }
}

// ─── Main Hook ──────────────────────────────────────────────────────────────
export function useContinuousAutoRouting() {
    const { excelData, updateExcelData } = useExcelData();
    const { groupingConfig } = useRouteCalculationStore();
    const isProcessingRef = useRef(false);
    const processedGroupSignatures = useRef<Set<string>>(new Set());
    const processedRefinements = useRef<Set<string>>(new Set());

    const excelDataRef = useRef(excelData);
    const updateExcelDataRef = useRef(updateExcelData);
    useEffect(() => { excelDataRef.current = excelData; }, [excelData]);
    useEffect(() => { updateExcelDataRef.current = updateExcelData; }, [updateExcelData]);

    const autoRoutingStatus = useDashboardStore(s => s.autoRoutingStatus);
    const setAutoRoutingStatus = useDashboardStore(s => s.setAutoRoutingStatus);
    const autoRoutingStatusRef = useRef(autoRoutingStatus);
    useEffect(() => { autoRoutingStatusRef.current = autoRoutingStatus; }, [autoRoutingStatus]);

    const runAutoRoutingRef = useRef<((forcedCourierName?: string) => Promise<void>) | null>(null);

    useEffect(() => {
        runAutoRoutingRef.current = async (forcedCourierName?: string) => {
            const currentData = excelDataRef.current;
            const currentStatus = autoRoutingStatusRef.current;

            if (!currentData?.orders || !currentData?.couriers) return;
            if (!currentStatus.isActive && !forcedCourierName) return;
            // Forced calls bypass global lock — they run independently
            if (isProcessingRef.current && !forcedCourierName) return;
            if (!forcedCourierName) isProcessingRef.current = true;

            try {
                const settings = localStorageUtils.getAllSettings();

                const isRealCourier = (name: any) => {
                    const n = normalizeCourierName(name);
                    return !!n && n !== 'Не назначено';
                };

                const getOrderCourier = (o: any) => {
                    if (o.courier && typeof o.courier === 'object') {
                        return o.courier.name || o.courier._id || o.courier.id || '';
                    }
                    return o.courierName || o.courierId || o.courier || '';
                };

                const totalSystemCouriers = currentData.couriers?.length || 0;
                const courierNamesWithRoutes = new Map<string, number>();
                let skippedGeocoding = 0;
                let skippedInRoutes = 0;
                let skippedNoCourier = 0;
                const seenSolo = new Set<string>();
                const soloGeoOrders: any[] = [];
                const routeTasks: { actualCourierName: string; groupOrders: any[]; groupSignature: string; windowLabel: string }[] = [];

                let eligibleOrders = currentData.orders.filter((o: any) => {
                    const status = String(o.status || '').toLowerCase();
                    const isCanceled = [
                        'отменен', 'отмена', 'удален', 'скасований', 'скасовано',
                        'canceled', 'cancelled', 'deleted'
                    ].includes(status);
                    if (isCanceled) return false;
                    const cname = getOrderCourier(o);
                    return isRealCourier(cname);
                });

                const processedOrderIds = new Set<string>();
                const normForced = forcedCourierName ? normalizeCourierName(forcedCourierName) : null;

                (currentData.routes || []).forEach((r: any) => {
                    const rCourier = normalizeCourierName(getCourierName(r.courier));
                    if (normForced && rCourier === normForced) return;
                    (r.orders || []).forEach((o: any) => {
                        const oid = getStableOrderId(o);
                        if (oid) processedOrderIds.add(oid);
                    });
                });

                eligibleOrders = currentData.orders.filter((o: any) => {
                    const status = String(o.status || '').toLowerCase();
                    const isCanceled = ['отменен', 'отмена', 'удален', 'скасований', 'скасовано', 'canceled', 'cancelled', 'deleted'].includes(status);
                    if (isCanceled) return false;
                    const oid = getStableOrderId(o);
                    if (oid && processedOrderIds.has(oid)) return false;
                    const cname = getOrderCourier(o);
                    const isReal = isRealCourier(cname);
                    if (!o.address || o.address.trim().length === 0) return false;
                    if (!isReal) return !o.coords?.lat;
                    return true;
                });

                if (eligibleOrders.length === 0) return;

                setAutoRoutingStatus({
                    totalCount: currentData.orders.length,
                    totalCouriers: totalSystemCouriers,
                    processedCount: processedOrderIds.size,
                    processedCouriers: courierNamesWithRoutes.size,
                    skippedGeocoding,
                    skippedInRoutes,
                    skippedNoCourier,
                    lastUpdate: Date.now()
                });

                if (forcedCourierName) {
                    toast.success(`Розрахунок для ${forcedCourierName} завершено`);
                }

                // Grouping
                const groupsMap = groupAllOrdersByTimeWindow(eligibleOrders, currentData.couriers, groupingConfig);
                for (const [courierNameKey, timeGroups] of Array.from(groupsMap.entries())) {
                    const isUnassigned = courierNameKey.toLowerCase().includes('unassigned') ||
                        courierNameKey === 'неназначенные' ||
                        courierNameKey === 'неизвестный курьер';

                    for (const group of timeGroups) {
                        const groupOrders = group.orders || [];
                        if (groupOrders.length === 0) continue;

                        const groupSignature = `${courierNameKey}|${group.windowLabel}|${groupOrders.map((o: any) => getStableOrderId(o)).sort().join(',')}`;
                        if (processedGroupSignatures.current.has(groupSignature)) continue;

                        if (isUnassigned) {
                            groupOrders.forEach(o => {
                                const oid = getStableOrderId(o);
                                if (oid && !o.coords?.lat && !seenSolo.has(oid)) {
                                    soloGeoOrders.push(o);
                                    seenSolo.add(oid);
                                }
                            });
                        } else {
                            routeTasks.push({
                                actualCourierName: group.courierName,
                                groupOrders,
                                groupSignature,
                                windowLabel: group.windowLabel
                            });
                        }
                    }
                }

                if (routeTasks.length === 0 && soloGeoOrders.length === 0) return;

                // ── PASS 0: FO GPS coordinates (instant, no API) ──────────────────
                const parseAddressGeoStr = (geoStr: string): { lat: number; lng: number } | null => {
                    if (!geoStr || geoStr === 'null' || geoStr === 'undefined') return null;
                    const s = String(geoStr);
                    const latM = s.match(/Lat\s*=\s*"?([\d.+-]+)"?/i);
                    const lngM = s.match(/Long\s*=\s*"?([\d.+-]+)"?/i);
                    if (latM && lngM) {
                        const lat = parseFloat(latM[1]);
                        const lng = parseFloat(lngM[1]);
                        if (!isNaN(lat) && !isNaN(lng) && lat !== 0 && lng !== 0 && Math.abs(lat) <= 90 && Math.abs(lng) <= 180) {
                            return { lat, lng };
                        }
                    }
                    const pair = s.match(/^([\-+]?\d+\.\d+)\s*,\s*([\-+]?\d+\.\d+)$/);
                    if (pair) {
                        const lat = parseFloat(pair[1]);
                        const lng = parseFloat(pair[2]);
                        if (!isNaN(lat) && !isNaN(lng) && Math.abs(lat) <= 90 && Math.abs(lng) <= 180) {
                            return { lat, lng };
                        }
                    }
                    return null;
                };

                let addressGeoApplied = 0;
                eligibleOrders.forEach((o: any) => {
                    if (o.coords?.lat) return;
                    const rawGeo = o.addressGeo || o.AddressGeo || o.address_geo || o.raw?.addressGeo || '';
                    const gps = parseAddressGeoStr(rawGeo);
                    if (!gps) return;

                    const zoneInfo = robustGeocodingService.findZoneForCoords(gps.lat, gps.lng);
                    const ctx = robustGeocodingService.getZoneContext();
                    const hasActiveZones = ctx && (ctx.activePolygons?.length > 0);

                    if (zoneInfo || !hasActiveZones) {
                        o.coords = { lat: gps.lat, lng: gps.lng };
                        o.locationType = 'GPS_FO';
                        o.geocodeScore = 1.0;
                        if (zoneInfo) {
                            o.kmlZone = zoneInfo.zoneName;
                            o.kmlHub = zoneInfo.hubName;
                        }
                        addressGeoApplied++;
                    } else {
                        o._addressGeoCandidate = gps;
                    }
                });

                if (addressGeoApplied > 0) {
                    const gpsMap = new Map<string, any>();
                    eligibleOrders.filter((o: any) => o.locationType === 'GPS_FO').forEach((o: any) => gpsMap.set(getStableOrderId(o), { ...o }));
                    updateExcelDataRef.current((prev: any) => {
                        const nO = (prev?.orders || []).map((o: any) => {
                            const up = gpsMap.get(getStableOrderId(o));
                            return up ? { ...o, ...up } : o;
                        });
                        return { ...prev, orders: nO };
                    }, false);
                }

                // ── PASS 1+2: Geocoding for orders without FO GPS ─────────────────
                const allOrdersToGeocode = eligibleOrders.filter((o: any) => !o.coords?.lat);

                const applyGeoResult = async (o: any, res: any) => {
                    if (!res?.best && o._addressGeoCandidate) {
                        o.coords = o._addressGeoCandidate;
                        o.locationType = 'GPS_FO_FALLBACK';
                        o.geocodeScore = 0.7;
                        return;
                    }
                    if (res?.best?.raw?.geometry?.location) {
                        // INNOVATION: Smart KML Center Fallback
                        // If geocoder returns city center (APPROXIMATE) or it's totally out of zone,
                        // we snap it directly to the geographic center of the KML zone it belongs to!
                        const locType = res.best.raw?.geometry?.location_type;
                        const isBadGeo = res.best.hasGeoErrors || locType === 'GEOMETRIC_CENTER' || locType === 'APPROXIMATE';
                        const orderZoneName = o.deliveryZone || o.kmlZone;
                        const ctx = robustGeocodingService.getZoneContext();
                        
                        if (isBadGeo && orderZoneName && ctx?.activePolygons?.length) {
                            const poly = ctx.activePolygons.find(p => p.name.toLowerCase() === orderZoneName.toLowerCase());
                            if (poly) {
                                let centerLat = NaN, centerLng = NaN;
                                if (poly.bounds && typeof poly.bounds.getNorthEast === 'function') {
                                    centerLat = (poly.bounds.getNorthEast().lat() + poly.bounds.getSouthWest().lat()) / 2;
                                    centerLng = (poly.bounds.getNorthEast().lng() + poly.bounds.getSouthWest().lng()) / 2;
                                } else if (poly.path && poly.path.length > 0) {
                                    centerLat = poly.path.reduce((sum: number, p: any) => sum + (typeof p.lat === 'function' ? p.lat() : Number(p.lat)), 0) / poly.path.length;
                                    centerLng = poly.path.reduce((sum: number, p: any) => sum + (typeof p.lng === 'function' ? p.lng() : Number(p.lng)), 0) / poly.path.length;
                                }
                                
                                if (!isNaN(centerLat) && !isNaN(centerLng)) {
                                    o.coords = { lat: centerLat, lng: centerLng };
                                    o.kmlZone = poly.name;
                                    o.kmlHub = poly.folderName;
                                    o.locationType = 'KML_CENTER_FALLBACK';
                                    o.geocodeScore = 0.5;
                                    o.streetNumberMatched = false;
                                    return; // Successfully snapped to KML center!
                                }
                            }
                        }

                        // Standard assignment
                        const loc = res.best.raw.geometry.location;
                        o.coords = { lat: Number(typeof loc.lat === 'function' ? loc.lat() : loc.lat), lng: Number(typeof loc.lng === 'function' ? loc.lng() : loc.lng) };
                        o.kmlZone = res.best.kmlZone || undefined;
                        o.kmlHub = res.best.kmlHub || undefined;
                        o.locationType = res.best.raw.geometry.location_type || undefined;
                        o.streetNumberMatched = res.best.streetNumberMatched;
                        o.geocodeScore = res.best.score ?? 0;
                        try {
                            const { RobustGeocodingService } = await import('../services/robust-geocoding/RobustGeocodingService');
                            RobustGeocodingService.saveToPermanentCache(o.address, o.coords.lat, o.coords.lng, o.geocodeScore);
                        } catch (e) {
                            console.warn('[Robot] Cache persist fail:', e);
                        }
                    }
                };

                if (allOrdersToGeocode.length > 0) {
                    // Pass 1: Turbo batch (fast, ~80% coverage)
                    const batchRequests = allOrdersToGeocode.map(o => ({
                        address: o.address,
                        options: { silent: true, turbo: true, expectedDeliveryZone: o.deliveryZone || o.kmlZone }
                    }));
                    const batchResults = await robustGeocodingService.batchGeocode(batchRequests, { turbo: true });
                    allOrdersToGeocode.forEach((o: any) => {
                        const addr = o.address || '';
                        const res = batchResults.get(addr.trim().toLowerCase());
                        applyGeoResult(o, res);
                    });

                    // Pass 2: Full retry for remaining
                    const stillFailed = allOrdersToGeocode.filter((o: any) => !o.coords?.lat);
                    if (stillFailed.length > 0) {
                        const RETRY_BATCH = 10;
                        for (let i = 0; i < stillFailed.length; i += RETRY_BATCH) {
                            const retryChunk = stillFailed.slice(i, i + RETRY_BATCH);
                            const retryResults = await robustGeocodingService.batchGeocode(
                                retryChunk.map(o => ({
                                    address: o.address,
                                    options: { turbo: false, maxVariants: 8, expectedDeliveryZone: o.deliveryZone || o.kmlZone }
                                })),
                                { turbo: false }
                            );
                            retryChunk.forEach((o: any) => {
                                const addr = o.address || '';
                                const res = retryResults.get(addr.trim().toLowerCase());
                                applyGeoResult(o, res);
                            });
                        }
                    }
                }

                // Save geocoding progress immediately
                const newlyGeocoded = allOrdersToGeocode.filter((o: any) => o.coords?.lat);
                if (newlyGeocoded.length > 0) {
                    const geoMap = new Map<string, any>();
                    newlyGeocoded.forEach((o: any) => geoMap.set(getStableOrderId(o), { ...o }));
                    updateExcelDataRef.current((prev: any) => {
                        const nO = (prev?.orders || []).map((o: any) => {
                            const up = geoMap.get(getStableOrderId(o));
                            return up ? { ...o, ...up } : o;
                        });
                        return { ...prev, orders: nO };
                    }, true);
                }

                const currentCourierByOrderId = new Map<string, string>();
                eligibleOrders.forEach((o: any) => {
                    const oid = getStableOrderId(o);
                    const cname = normalizeCourierName(getOrderCourier(o));
                    if (oid && cname) currentCourierByOrderId.set(oid, cname);
                });

                // ── TURBO PARALLEL ROUTING ────────────────────────────────────────
                // 10 concurrent workers, each uses Promise.any race identical to /map tab
                const CONCURRENCY = 10;
                const taskQueue = [...routeTasks];
                const updatedNames = new Set<string>();

                const runTask = async (): Promise<void> => {
                    while (taskQueue.length > 0) {
                        const task = taskQueue.shift();
                        if (!task) break;
                        const { actualCourierName, groupOrders: chunkOrders, groupSignature } = task;

                        try {
                            const newRoute: any = {
                                id: `autoroute_${Date.now()}_rnd${Math.floor(Math.random() * 10000)}`,
                                courier: actualCourierName,
                                orders: [...chunkOrders],
                                totalDistance: 0,
                                totalDuration: 0,
                                isOptimized: false,
                                createdAt: Date.now(),
                                isAutoGenerated: true,
                                hasGeoErrors: chunkOrders.some((o: any) =>
                                    needsAddressClarification({
                                        locationType: o.locationType,
                                        streetNumberMatched: o.streetNumberMatched,
                                        hasCoords: !!o.coords?.lat,
                                        geocodeScore: o.geocodeScore
                                    }) || o._kmlRejected
                                )
                            };

                            const safeNum = (val: any) => {
                                if (val === null || val === undefined) return null;
                                const parsed = parseFloat(String(val).replace(',', '.'));
                                return isNaN(parsed) ? null : parsed;
                            };

                            const points: { lat: number; lng: number }[] = [];
                            const sLat = safeNum(settings?.defaultStartLat);
                            const sLng = safeNum(settings?.defaultStartLng);

                            if (sLat !== null && sLng !== null) {
                                points.push({ lat: sLat, lng: sLng });
                            }

                            chunkOrders.forEach((o: any) => {
                                const oLat = safeNum(o.coords?.lat);
                                const oLng = safeNum(o.coords?.lng);
                                if (oLat !== null && oLng !== null) {
                                    const isApproximate = ['APPROXIMATE_ZONE', 'APPROXIMATE_CITY'].includes(o.locationType || '');
                                    if (isApproximate) {
                                        points.push({ lat: oLat, lng: oLng });
                                        return;
                                    }
                                    
                                    const zoneInfo = robustGeocodingService.findZoneForCoords(oLat, oLng);
                                    let isAnomaly = false;
                                    
                                    if (!zoneInfo) {
                                        const ctx = robustGeocodingService.getZoneContext();
                                        if (ctx && (ctx.activePolygons?.length > 0 || ctx.allPolygons?.length > 0)) {
                                            o._kmlRejected = true;
                                            newRoute.hasGeoErrors = true; // Flag the route as having an outlier
                                            
                                            // Умная проверка: отличаем реальный "вылет" за зону (2-5 км) от бага геокодера (500+ км)
                                            if (sLat !== null && sLng !== null) {
                                                const distFromHub = haversineDistance(sLat, sLng, oLat, oLng) / 1000;
                                                const maxAllowed = settings?.anomalyMaxLegDistanceKm || 25;
                                                
                                                if (distFromHub > maxAllowed) {
                                                    isAnomaly = true;
                                                    // Снапим кривую координату к Хабу, чтобы не сломать километраж и не отдалить карту
                                                    o.coords = { lat: sLat, lng: sLng };
                                                    points.push({ lat: sLat, lng: sLng });
                                                }
                                            }
                                        }
                                    }
                                    
                                    if (!isAnomaly) {
                                        // Координата адекватная (либо внутри зоны, либо недалеко вылетела). Доверяем ей!
                                        points.push({ lat: oLat, lng: oLng });
                                    }
                                } else {
                                    newRoute.hasGeoErrors = true; // No coordinates at all
                                }
                            });

                            const eLat = safeNum(settings?.defaultEndLat);
                            const eLng = safeNum(settings?.defaultEndLng);
                            if (eLat !== null && eLng !== null) {
                                points.push({ lat: eLat, lng: eLng });
                            } else if (points.length > 0) {
                                points.push(points[0]);
                            }

                            // Keep ALL assigned orders in the route, never drop them
                            newRoute.orders = [...chunkOrders];

                            if (points.length >= 2) {
                                const uniquePoints = points.filter((p, i) =>
                                    i === 0 || Math.abs(p.lat - points[i - 1].lat) > 0.00001 || Math.abs(p.lng - points[i - 1].lng) > 0.00001
                                );

                                if (uniquePoints.length >= 2) {
                                    const hasHub = sLat !== null && sLng !== null;
                                    // ⚡ TURBO RACE — identical to /map tab OSRM call
                                    const winner = await turboRouteRace(uniquePoints, settings?.yapikoOsrmUrl?.trim() || undefined);

                                    newRoute.totalDistanceKm = parseFloat((winner.dist / 1000).toFixed(2));
                                    newRoute.totalDistance = parseFloat((winner.dist / 1000).toFixed(2));
                                    newRoute.totalDuration = Math.round(winner.dur / 60);
                                    newRoute.totalDurationMin = Math.round(winner.dur / 60);
                                    newRoute.isOptimized = true;
                                    newRoute.routingEngine = winner.eng;
                                    if (winner.geometry) newRoute.geometry = winner.geometry;

                                    if (hasHub) {
                                        newRoute.startAddress = settings.defaultStartAddress || `${sLat}, ${sLng}`;
                                        newRoute.endAddress = settings.defaultEndAddress || newRoute.startAddress;
                                    }
                                } else {
                                    newRoute.hasGeoErrors = true;
                                }
                            }

                            // Save route immediately
                            updateExcelDataRef.current((prev: any) => {
                                if (!prev) return prev;
                                const chunkIds = new Set(chunkOrders.map((o: any) => getStableOrderId(o)));
                                const nonMatchingRoutes = (prev.routes || []).filter((r: any) =>
                                    !r.isAutoGenerated || !r.orders.some((ro: any) => chunkIds.has(getStableOrderId(ro)))
                                );
                                const orderMap = new Map();
                                chunkOrders.forEach((o: any) => orderMap.set(getStableOrderId(o), { ...o }));
                                const updatedOrders = (prev.orders || []).map((o: any) => orderMap.get(getStableOrderId(o)) || o);
                                return { ...prev, orders: updatedOrders, routes: [...nonMatchingRoutes, newRoute], lastModified: Date.now() };
                            }, true);

                            processedGroupSignatures.current.add(groupSignature);
                            updatedNames.add(actualCourierName);

                        } catch (taskErr) {
                            console.error('[Robot] Task failed:', groupSignature, taskErr);
                        }
                    }
                };

                // ⚡ TRUE PARALLEL: 10 workers running simultaneously
                await Promise.all(Array.from({ length: CONCURRENCY }, () => runTask()));

                if (updatedNames.size > 0) {
                    toast.success(`Робот: Оновив ${updatedNames.size} кур'єрів`, { icon: '🤖' });
                }

                // Refinement pass for geo-uncertain orders
                try {
                    const needsRef = currentData.orders.filter((o: any) => {
                        const sid = getStableOrderId(o);
                        const rk = `${sid}_${o.address}`;
                        if (processedRefinements.current.has(rk)) return false;
                        return needsAddressClarification({
                            locationType: o.locationType,
                            streetNumberMatched: o.streetNumberMatched,
                            hasCoords: !!o.coords?.lat
                        });
                    });

                    if (needsRef.length > 0) {
                        const batch = needsRef.slice(0, 50);
                        const requests = batch.map(o => ({
                            address: o.address,
                            options: { turbo: false, forceCityBias: true, silent: true }
                        }));
                        const results = await robustGeocodingService.batchGeocode(requests, { turbo: false });
                        const updates = new Map<string, any>();
                        for (const o of batch) {
                            const sid = getStableOrderId(o);
                            processedRefinements.current.add(`${sid}_${o.address}`);
                            const addr = o.address || '';
                            const r = results.get(addr.trim().toLowerCase());
                            if (r?.best?.raw?.geometry?.location) {
                                const loc = r.best.raw.geometry.location;
                                updates.set(sid, {
                                    ...o,
                                    coords: { lat: Number(loc.lat), lng: Number(loc.lng) },
                                    kmlZone: r.best.kmlZone || undefined,
                                    kmlHub: r.best.kmlHub || undefined,
                                    locationType: r.best.raw.geometry.location_type || undefined,
                                    streetNumberMatched: r.best.streetNumberMatched
                                });
                            }
                        }
                        if (updates.size > 0) {
                            updateExcelDataRef.current((prev: any) => {
                                const nO = (prev?.orders || []).map((order: any) => {
                                    const u = updates.get(getStableOrderId(order));
                                    return u ? { ...order, ...u } : order;
                                });
                                const nR = (prev?.routes || []).map((route: any) => ({
                                    ...route,
                                    orders: route.orders.map((ro: any) => {
                                        const u = updates.get(getStableOrderId(ro));
                                        return u ? { ...ro, ...u } : ro;
                                    })
                                }));
                                return { ...prev, orders: nO, routes: nR };
                            }, true);
                        }
                    }
                } catch { }

            } catch (err) {
                console.error('[AutoRouting] Critical failure:', err);
            } finally {
                isProcessingRef.current = false;
                setAutoRoutingStatus({ lastUpdate: Date.now() });
            }
        };
    }, [robustGeocodingService, setAutoRoutingStatus]);

    // Interval runner (when autorouting is active)
    useEffect(() => {
        if (!autoRoutingStatus.isActive) {
            isProcessingRef.current = false;
            return;
        }
        const run = () => runAutoRoutingRef.current?.();
        const intervalId = setInterval(run, 15000);
        const t = setTimeout(run, 500);
        return () => {
            clearInterval(intervalId);
            clearTimeout(t);
        };
    }, [autoRoutingStatus.isActive]);

    // Manual trigger listener (always active — for forced courier recalc)
    useEffect(() => {
        const forceHandler = async (e: any) => {
            const target = e.detail?.courierName;
            const mode = e.detail?.mode;

            if (mode === 'frontend') {
                console.log(`[AutoRouting] Force frontend run for ${target || 'all'}`);
                processedGroupSignatures.current.clear();
                runAutoRoutingRef.current?.(target);
            } else {
                console.log(`[AutoRouting] Redirecting to BACKEND Turbo Robot${target ? ` for ${target}` : ''}`);
                processedGroupSignatures.current.clear();
                try {
                    toast.loading(target ? `Синхронизація ${target}...` : 'Запуск Турбо-Робота...', { id: 'turbo-trigger' });
                    const token = localStorage.getItem('km_access_token') || localStorage.getItem('token');
                    const { divisionId, apiDateShift } = useDashboardStore.getState();
                    const res = await fetch(`${API_URL}/api/turbo/priority`, {
                        method: 'POST',
                        headers: {
                            'Content-Type': 'application/json',
                            'Authorization': `Bearer ${token}`
                        },
                        body: JSON.stringify({
                            divisionId,
                            date: apiDateShift,
                            force: true,
                            ...(target ? { courierName: target } : {})
                        })
                    });
                    if (!res.ok) {
                        const err = await res.json();
                        throw new Error(err.error || err.message || `Server error ${res.status}`);
                    }
                    toast.success(target ? `Расчет для ${target} запущен` : 'Турбо-Робот запущен', { id: 'turbo-trigger' });
                } catch (err: any) {
                    console.error('[AutoRouting] Backend trigger failed:', err);
                    toast.error(`Ошибка запуска: ${err.message}`, { id: 'turbo-trigger' });
                    toast('Переход на локальный расчет...', { id: 'turbo-fallback' });
                    runAutoRoutingRef.current?.(target);
                }
            }
        };

        window.addEventListener('km-force-auto-routing', forceHandler);
        return () => {
            window.removeEventListener('km-force-auto-routing', forceHandler);
        };
    }, []);

    // Structural trigger (new orders detected)
    const lastSigRef = useRef('');
    useEffect(() => {
        if (!autoRoutingStatus.isActive || !excelData?.orders) return;
        const sig = excelData.orders
            .map((o: any) => `${getStableOrderId(o)}|${o.address}|${getCourierName(o.courier)}|${o.status}`)
            .sort().join(',');
        if (sig !== lastSigRef.current) {
            lastSigRef.current = sig;
            const t = setTimeout(() => runAutoRoutingRef.current?.(), 1000);
            return () => clearTimeout(t);
        }
    }, [excelData?.orders, autoRoutingStatus.isActive]);
}

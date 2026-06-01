import { test, expect, describe } from 'vitest';
import { groupOrdersByTimeWindow } from '../routeCalculationHelpers';
import { Order } from '../../../types';

describe('routeCalculationHelpers - Dispatch Wave Grouping and Trip Guard', () => {
    
    // Вспомогательная функция для генерации фейковых заказов
    const createTestOrder = (
        id: string, 
        status: string, 
        planned: number,
        pickup: number | null,
        execution: number | null
    ): Order => ({
        id,
        address: 'Test Addr',
        status,
        readyAtSource: planned - 15 * 60 * 1000,
        deadlineAt: planned,
        handoverAt: pickup,
        statusTimings: {
            deliveringAt: pickup || undefined,
            completedAt: execution || undefined
        },
        coords: { lat: 49.8, lng: 73.1 }, // Karaganda approx
        deliveryZone: 'ZoneA',
        isActive: true,
        isCompleted: status === 'Исполнен',
        isArchived: false,
        totalDistance: 1,
        totalDuration: 1,
        orders: [],
        geocodingSuccess: true,
        courierName: 'Test Courier',
        originalAddress: 'Test Addr'
    });

    test('should split physically different trips based on completedAt (v9.1 overlap guard)', () => {
        // Ситуация: Курьер взял 2 заказа (рейс 1) и доставил их. 
        // Затем вернулся и взял 3-й заказ (рейс 2).
        
        const now = 1000000000;
        const o1 = createTestOrder('1', 'Исполнен', now + 60*60*1000, now, now + 20*60*1000); // Pickup 0, Delivered +20m
        const o2 = createTestOrder('2', 'Исполнен', now + 60*60*1000, now + 5*60*1000, now + 30*60*1000); // Pickup +5m, Delivered +30m
        
        // 3-й заказ взят курьером (+45m) — ПОСЛЕ того как оба предыдущих УЖЕ доставлены (max: +30m).
        const o3 = createTestOrder('3', 'Доставляется', now + 120*60*1000, now + 45*60*1000, null); 

        const orders = [o1, o2, o3];
        const groups = groupOrdersByTimeWindow(orders, 'c1', 'Test Courier');

        // Ожидаем 2 группы, потому что o3 не может быть в первой (курьер уже доставил o2 к моменту взятия o3)
        expect(groups).toHaveLength(2);
        expect(groups[0].orders.map(o => o.id)).toEqual(['1', '2']);
        expect(groups[1].orders.map(o => o.id)).toEqual(['3']);
        expect(groups[1].splitReason).toContain('Предыдущий заказ уже исполнен');
    });

    test('should group orders within 15min dispatch wave', () => {
        // Ситуация: Курьер взял 3 заказа подряд в течение 15 минут. 
        // Они должны стать одним рейсом, несмотря на разброс planned time
        
        const now = 1000000000;
        const o1 = createTestOrder('1', 'Доставляется', now + 120*60*1000, now, null); 
        const o2 = createTestOrder('2', 'Доставляется', now + 130*60*1000, now + 10*60*1000, null); // Pickup +10m 
        const o3 = createTestOrder('3', 'Доставляется', now + 140*60*1000, now + 14*60*1000, null); // Pickup +14m

        // 4-й заказ взят через 35 минут. Это уже новый рейс, т.к. окно диспетчеризации (15 минут) закрылось.
        const o4 = createTestOrder('4', 'Доставляется', now + 150*60*1000, now + 35*60*1000, null); 

        const orders = [o1, o2, o3, o4];
        const groups = groupOrdersByTimeWindow(orders, 'c1', 'Test Courier');

        expect(groups).toHaveLength(2);
        expect(groups[0].orders.map(o => o.id)).toEqual(['1', '2', '3']);
        expect(groups[1].orders.map(o => o.id)).toEqual(['4']);
        expect(groups[1].splitReason).toContain('Время'); // 35m > 15m
    });
});

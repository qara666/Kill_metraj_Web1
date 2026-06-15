const { Kafka } = require('kafkajs');
const logger = require('../utils/logger');
const cacheService = require('../services/CacheService');

/**
 * Kafka-консьюмер для событий CDC дашборда
 * Принимает события Debezium CDC из PostgreSQL и рассылает их WebSocket-клиентам
 */
class DashboardConsumer {
    constructor(io) {
        this.io = io;
        this.isEnabled = process.env.CDC_ENABLED === 'true';
        this.isRunning = false;

        if (!this.isEnabled) {
            logger.info('CDC-консьюмер отключен. Установите CDC_ENABLED=true для включения.');
            return;
        }

        this.kafka = new Kafka({
            clientId: 'kill-metraj-backend',
            brokers: (process.env.KAFKA_BROKER || 'localhost:9092').split(',')
        });

        this.consumer = this.kafka.consumer({
            groupId: 'dashboard-updates',
            sessionTimeout: 30000,
            heartbeatInterval: 3000
        });
    }

    /**
     * Запуск потребления сообщений Kafka
     */
    async start() {
        if (!this.isEnabled) {
            return;
        }

        try {
            await this.consumer.connect();
            logger.info('Kafka-консьюмер подключен');

            // Подписка на топик Debezium
            const topic = process.env.KAFKA_TOPIC || 'kill_metraj.public.api_dashboard_cache';
            await this.consumer.subscribe({
                topic: topic,
                fromBeginning: false
            });

            logger.info(`Подписка на топик: ${topic}`);

            // Запуск обработки сообщений
            await this.consumer.run({
                eachMessage: async ({ topic, partition, message }) => {
                    try {
                        const event = JSON.parse(message.value.toString());
                        await this.handleDashboardUpdate(event);
                    } catch (error) {
                        logger.error('Ошибка обработки сообщения Kafka:', error);
                    }
                }
            });

            this.isRunning = true;
            logger.info('Kafka-консьюмер ожидает обновлений дашборда');
        } catch (error) {
            logger.error('Не удалось запустить Kafka-консьюмер:', error);
            this.isEnabled = false;
        }
    }

    /**
     * Обработка события обновления дашборда от Debezium
     */
    async handleDashboardUpdate(event) {
        try {
            if (!event || !event.payload) {
                logger.warn('Получено неверное событие CDC:', event);
                return;
            }

            logger.info('Получено обновление дашборда от Debezium CDC', {
                id: event.id,
                status_code: event.status_code
            });

            await cacheService.invalidateAll();
            logger.debug('Кэш сброшен из-за события CDC');

            // v8.1 BANDWIDTH: Room-based targeted emits instead of O(N socket) iteration.
            // Collect unique divisionIds from connected sockets, then send ONE filtered
            // payload per division room instead of one per socket.
            const sockets = await this.io.fetchSockets();
            if (sockets.length === 0) {
                logger.debug('Нет подключенных WebSocket-клиентов, пропуск рассылки');
                return;
            }

            const fullPayload = event.payload;
            const divisionsSeen = new Set();

            for (const socketInstance of sockets) {
                const socket = this.io.sockets.sockets.get(socketInstance.id);
                if (!socket || !socket.user) continue;
                const user = socket.user;

                if (user.role === 'admin') {
                    // Admin gets full payload — sent once via 'div:all' room below
                    continue;
                }

                const divId = String(user.divisionId || '');
                if (!divId || divisionsSeen.has(divId)) continue;
                divisionsSeen.add(divId);

                // Filter payload to this division only
                const divPayload = {
                    ...fullPayload,
                    orders: (fullPayload.orders || []).filter(
                        o => String(o.departmentId) === divId
                    ),
                    couriers: (fullPayload.couriers || []).filter(
                        c => String(c.departmentId) === divId
                    )
                };

                this.io.to(`div:${divId}`).emit('dashboard:update', {
                    data: divPayload,
                    timestamp: event.created_at,
                    status: event.status_code,
                    source: 'cdc'
                });
            }

            // Send full payload to admins (div:all room)
            this.io.to('div:all').emit('dashboard:update', {
                data: fullPayload,
                timestamp: event.created_at,
                status: event.status_code,
                source: 'cdc'
            });

            logger.info(`Обновление CDC разослано: ${divisionsSeen.size} отделов + admins`);
        } catch (error) {
            logger.error('Ошибка обработки обновления дашборда:', error);
        }
    }

    /**
     * Остановка потребления и отключение
     */
    async stop() {
        if (this.isRunning) {
            try {
                await this.consumer.disconnect();
                this.isRunning = false;
                logger.info('Kafka-консьюмер остановлен');
            } catch (error) {
                logger.error('Ошибка при остановке Kafka-консьюмера:', error);
            }
        }
    }

    /**
     * Проверка здоровья Kafka консьюмера
     */
    async healthCheck() {
        if (!this.isEnabled) {
            return { healthy: true, message: 'CDC disabled' };
        }

        if (!this.isRunning) {
            return { healthy: false, error: 'Consumer not running' };
        }

        return {
            healthy: true,
            status: 'running',
            enabled: this.isEnabled
        };
    }
}

module.exports = DashboardConsumer;

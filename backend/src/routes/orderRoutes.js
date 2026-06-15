const express = require('express');
const router = express.Router();
const { sequelize } = require('../config/database');
const { authenticateToken } = require('../middleware/auth');
const logger = require('../utils/logger');

/**
 * PATCH /api/v1/orders/:orderNumber/payment-method
 * Upsert a manual payment method override for an order
 */
router.patch('/:orderNumber/payment-method', authenticateToken, async (req, res) => {
    try {
        const { orderNumber } = req.params;
        const { paymentMethod } = req.body;

        if (!paymentMethod) {
            return res.status(400).json({ success: false, error: 'Payment method is required' });
        }

        logger.info(`Manual override: Setting order #${orderNumber} to ${paymentMethod}`);

        await sequelize.query(`
            INSERT INTO manual_order_overrides (order_number, payment_method, updated_at)
            VALUES (:orderNumber, :paymentMethod, NOW())
            ON CONFLICT (order_number) 
            DO UPDATE SET payment_method = EXCLUDED.payment_method, updated_at = NOW()
        `, {
            replacements: { orderNumber, paymentMethod }
        });

        // Инвалидировать кэш для немедленного отражения изменений
        const cacheService = require('../services/CacheService');
        await cacheService.invalidateAll();

        res.json({
            success: true,
            message: `Способ оплаты для заказа #${orderNumber} изменен на ${paymentMethod}`
        });

    } catch (error) {
        logger.error('Error updating payment method override:', error);
        res.status(500).json({ success: false, error: 'Внутренняя ошибка сервера' });
    }
});

/**
 * POST /api/v1/orders/overrides/bulk
 * Upsert bulk manual overrides (settlements, manual geocoding, statuses, etc.) globally
 */
router.post('/overrides/bulk', authenticateToken, async (req, res) => {
    try {
        const { overrides } = req.body;
        if (!overrides || typeof overrides !== 'object') {
            return res.status(400).json({ success: false, error: 'Overrides object is required' });
        }

        const entries = Object.entries(overrides);
        if (entries.length === 0) {
            return res.json({ success: true, message: 'No overrides to update' });
        }

        logger.info(`Bulk manual override: Updating ${entries.length} orders`);

        // Use transaction for bulk upsert
        const transaction = await sequelize.transaction();
        try {
            for (const [orderId, overrideData] of entries) {
                await sequelize.query(`
                    INSERT INTO global_order_overrides (order_id, override_data, updated_at)
                    VALUES (:orderId, :overrideData, NOW())
                    ON CONFLICT (order_id)
                    DO UPDATE SET override_data = EXCLUDED.override_data, updated_at = NOW()
                `, {
                    replacements: { orderId: String(orderId), overrideData: JSON.stringify(overrideData) },
                    transaction
                });
            }
            await transaction.commit();
        } catch (txnError) {
            await transaction.rollback();
            throw txnError;
        }

        res.json({
            success: true,
            message: `Успешно обновлено ${entries.length} заказов`
        });

    } catch (error) {
        logger.error('Error in bulk overrides:', error);
        res.status(500).json({ success: false, error: 'Внутренняя ошибка сервера' });
    }
});

module.exports = router;

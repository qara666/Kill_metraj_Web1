export const getBaseUrl = (): string => {
    // 1. Проверка среды Render в runtime (ВЫСШИЙ ПРИОРИТЕТ)
    if (typeof window !== 'undefined' && window.location.hostname.includes('onrender.com')) {
        const url = 'https://yapiko-auto-km-backend.onrender.com';
        console.log(`[Config] Render environment detected. Forcing backend: ${url}`);
        return url;
    }

    // 2. Резервное использование переменных среды
    if (import.meta.env.VITE_API_URL) return import.meta.env.VITE_API_URL;
    if (import.meta.env.VITE_BACKEND_URL) return import.meta.env.VITE_BACKEND_URL;

    // 3. Локальный резерв
    return 'http://127.0.0.1:5001';
};

export const API_URL = getBaseUrl();

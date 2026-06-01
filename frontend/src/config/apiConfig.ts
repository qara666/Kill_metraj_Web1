export const getBaseUrl = (): string => {
    // 1. Используем переменные окружения, которые можно задать в Render Dashboard
    if (import.meta.env.VITE_API_URL) return import.meta.env.VITE_API_URL;
    if (import.meta.env.VITE_BACKEND_URL) return import.meta.env.VITE_BACKEND_URL;

    // 2. Локальный резерв
    return 'http://127.0.0.1:5001';
};

export const API_URL = getBaseUrl();

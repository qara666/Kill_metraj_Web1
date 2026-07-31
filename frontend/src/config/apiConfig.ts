export const getBaseUrl = (): string => {
    // 1. Используем переменные окружения, которые можно задать в Render Dashboard
    if (import.meta.env.VITE_API_URL) return import.meta.env.VITE_API_URL;
    if (import.meta.env.VITE_BACKEND_URL) return import.meta.env.VITE_BACKEND_URL;

    // 2. В dev режиме используем пустую строку — запросы идут через прокси Vite (/api → 5001)
    //    В production — пустая строка тоже корректна (same-origin)
    if (import.meta.env.DEV) return '';

    // 3. Фолбэк для нестандартных окружений
    return '';
};

export const API_URL = getBaseUrl();

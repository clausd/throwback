/**
 * CrudClient - JavaScript client for CrudApp APIs
 *
 * @version 1.0.0
 *
 * Usage:
 *   const api = new CrudClient('/api');
 *   await api.login('user', 'pass');
 *   const todos = await api.table('todos').list();
 */
class CrudClient {
    /**
     * Create a new CrudClient
     * @param {string} baseUrl - Base URL of the API (e.g., '/api' or 'https://example.com/api')
     * @param {Object} options - Optional settings
     * @param {string} options.token - Initial auth token
     */
    constructor(baseUrl, options = {}) {
        this.baseUrl = baseUrl.replace(/\/$/, '');
        this.token = options.token || localStorage.getItem('crud_token');
    }

    /**
     * Set the authentication token
     * @param {string|null} token - Token to set, or null to clear
     */
    setToken(token) {
        this.token = token;
        if (token) {
            localStorage.setItem('crud_token', token);
        } else {
            localStorage.removeItem('crud_token');
        }
    }

    /**
     * Make an API request
     * @param {string} method - HTTP method
     * @param {string} path - API path
     * @param {Object} data - Request body data (for POST/PUT)
     * @returns {Promise<Object>} Response data
     */
    async request(method, path, data = null) {
        const url = `${this.baseUrl}/${path}`;
        const options = {
            method,
            headers: {
                'Content-Type': 'application/json'
            }
        };

        if (this.token) {
            options.headers['Authorization'] = `Bearer ${this.token}`;
        }

        if (data && method !== 'GET') {
            options.body = JSON.stringify(data);
        }

        const response = await fetch(url, options);

        let json;
        try {
            json = await response.json();
        } catch (e) {
            json = { error: 'Invalid response from server' };
        }

        if (!response.ok) {
            const error = new Error(json.error || `HTTP ${response.status}`);
            error.status = response.status;
            error.response = json;
            throw error;
        }

        return json;
    }

    /**
     * Login with username and password
     * @param {string} username
     * @param {string} password
     * @returns {Promise<Object>} { token, expires }
     */
    async login(username, password) {
        const result = await this.request('POST', 'login', { username, password });
        this.setToken(result.token);
        return result;
    }

    /**
     * Logout and clear token
     * @returns {Promise<Object>}
     */
    async logout() {
        try {
            await this.request('POST', 'logout');
        } catch (e) {
            // Ignore logout errors
        }
        this.setToken(null);
        return { ok: true };
    }

    /**
     * Check if user is logged in (has token)
     * @returns {boolean}
     */
    isLoggedIn() {
        return !!this.token;
    }

    /**
     * Get a table interface for CRUD operations
     * @param {string} name - Table name
     * @returns {Object} Table interface with list, get, create, update, delete methods
     */
    table(name) {
        const client = this;
        return {
            /**
             * List records
             * @param {Object} params - Query params (limit, offset, etc.)
             * @returns {Promise<Object>} { data: [...], limit, offset }
             */
            async list(params = {}) {
                const query = new URLSearchParams(params).toString();
                const path = query ? `${name}?${query}` : name;
                return client.request('GET', path);
            },

            /**
             * Get single record by ID
             * @param {number|string} id
             * @returns {Promise<Object>} Record data
             */
            async get(id) {
                return client.request('GET', `${name}/${id}`);
            },

            /**
             * Create new record
             * @param {Object} data - Record data (without id)
             * @returns {Promise<Object>} Created record with id
             */
            async create(data) {
                return client.request('POST', name, data);
            },

            /**
             * Update existing record
             * @param {number|string} id - Record ID
             * @param {Object} data - Fields to update
             * @returns {Promise<Object>} Updated record
             */
            async update(id, data) {
                return client.request('POST', name, { id, ...data });
            },

            /**
             * Delete record
             * @param {number|string} id
             * @returns {Promise<Object>} { deleted: id }
             */
            async delete(id) {
                return client.request('DELETE', `${name}/${id}`);
            }
        };
    }
}

// Export for module systems
if (typeof module !== 'undefined' && module.exports) {
    module.exports = CrudClient;
}

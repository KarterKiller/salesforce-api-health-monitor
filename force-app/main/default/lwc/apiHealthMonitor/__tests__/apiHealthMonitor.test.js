import { createElement } from 'lwc';
import ApiHealthMonitor from 'c/apiHealthMonitor';
import getDashboard from '@salesforce/apex/ApiHealthController.getDashboard';
import getLatencyHistory from '@salesforce/apex/ApiHealthController.getLatencyHistory';
import checkNow from '@salesforce/apex/ApiHealthController.checkNow';

jest.mock('@salesforce/apex/ApiHealthController.getDashboard', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/ApiHealthController.getLatencyHistory', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/ApiHealthController.checkNow', () => ({ default: jest.fn() }), { virtual: true });
const flushPromises = () => new Promise((resolve) => setTimeout(resolve, 0));
const dashboard = { endpoints: [{ configKey: 'Demo', displayName: 'Demo API', state: 'healthy', lastCheckedAt: '2026-10-26T08:20:33.000Z', lastStatusCode: 200, lastDurationMs: 42 }], healthyCount: 1, failedCount: 0, unknownCount: 0, averageLatencyMs: 42 };

describe('c-api-health-monitor', () => {
    afterEach(() => { while (document.body.firstChild) document.body.removeChild(document.body.firstChild); jest.clearAllMocks(); });
    it('shows KPI cards, a formatted endpoint and latency chart', async () => {
        getDashboard.mockResolvedValue(dashboard);
        getLatencyHistory.mockResolvedValue([{ configKey: 'Demo', checkedAt: '2026-10-26T08:20:33.000Z', statusCode: 200, durationMs: 42, success: true }, { configKey: 'Demo', checkedAt: '2026-10-26T08:21:33.000Z', statusCode: 503, durationMs: 75, success: false }]);
        const element = createElement('c-api-health-monitor', { is: ApiHealthMonitor }); document.body.appendChild(element);
        element.shadowRoot.querySelector('lightning-button').click(); await flushPromises(); await flushPromises(); await flushPromises();
        expect(element.shadowRoot.textContent).toContain('Healthy APIs');
        expect(element.shadowRoot.textContent).toContain('42 ms');
        expect(element.shadowRoot.querySelector('.healthy-badge').textContent).toContain('Healthy');
        expect(element.shadowRoot.querySelector('svg')).not.toBeNull();
        expect(Number(element.shadowRoot.querySelector('.failed-point').getAttribute('cy'))).toBeLessThan(92);
    });
    it('shows useful empty states when no configurations or history exist', async () => {
        getDashboard.mockResolvedValue({ endpoints: [], healthyCount: 0, failedCount: 0, unknownCount: 0, averageLatencyMs: null }); getLatencyHistory.mockResolvedValue([]);
        const element = createElement('c-api-health-monitor', { is: ApiHealthMonitor }); document.body.appendChild(element);
        element.shadowRoot.querySelector('lightning-button').click(); await flushPromises(); await flushPromises(); await flushPromises();
        expect(element.shadowRoot.textContent).toContain('No active endpoint configurations');
        expect(element.shadowRoot.textContent).toContain('Latency history will appear');
    });
    it('asks for another observation when chart history has only one measurement', async () => {
        getDashboard.mockResolvedValue(dashboard); getLatencyHistory.mockResolvedValue([{ configKey: 'Demo', checkedAt: '2026-10-26T08:20:33.000Z', statusCode: 200, durationMs: 42, success: true }]);
        const element = createElement('c-api-health-monitor', { is: ApiHealthMonitor }); document.body.appendChild(element);
        element.shadowRoot.querySelector('lightning-button').click(); await flushPromises(); await flushPromises(); await flushPromises();
        expect(element.shadowRoot.textContent).toContain('Record one more completed HTTP check');
        expect(element.shadowRoot.querySelector('svg')).toBeNull();
    });
    it('does not convert missing latency to zero or plot it as a completed check', async () => {
        getDashboard.mockResolvedValue(dashboard); getLatencyHistory.mockResolvedValue([{ configKey: 'Missing', checkedAt: '2026-10-26T08:20:33.000Z', statusCode: 503, durationMs: null, success: false }, { configKey: 'TransportError', checkedAt: '2026-10-26T08:20:34.000Z', statusCode: null, durationMs: 1, success: false }, { configKey: 'Healthy', checkedAt: '2026-10-26T08:21:33.000Z', statusCode: 200, durationMs: 100, success: true }, { configKey: 'FailedHttp', checkedAt: '2026-10-26T08:22:33.000Z', statusCode: 503, durationMs: 567, success: false }]);
        const element = createElement('c-api-health-monitor', { is: ApiHealthMonitor }); document.body.appendChild(element);
        element.shadowRoot.querySelector('lightning-button').click(); await flushPromises(); await flushPromises(); await flushPromises();
        expect(element.shadowRoot.querySelectorAll('circle')).toHaveLength(2);
        expect(Number(element.shadowRoot.querySelector('.failed-point').getAttribute('cy'))).toBeLessThan(92);
        expect(element.shadowRoot.textContent).toContain('HTTP 503: 567 ms');
        expect(element.shadowRoot.querySelector('svg').getAttribute('preserveAspectRatio')).toBe('xMidYMid meet');
    });
    it('shows a helpful error when a check cannot run', async () => {
        getDashboard.mockResolvedValue(dashboard); getLatencyHistory.mockResolvedValue([]); checkNow.mockRejectedValue({ body: { message: 'Not authorized' } });
        const element = createElement('c-api-health-monitor', { is: ApiHealthMonitor }); document.body.appendChild(element);
        element.shadowRoot.querySelector('lightning-button').click(); await flushPromises(); await flushPromises(); await flushPromises();
        Array.from(element.shadowRoot.querySelectorAll('lightning-button')).find((button) => button.dataset.key === 'Demo').click(); await flushPromises(); await flushPromises();
        expect(element.shadowRoot.textContent).toContain('Not authorized');
    });
});

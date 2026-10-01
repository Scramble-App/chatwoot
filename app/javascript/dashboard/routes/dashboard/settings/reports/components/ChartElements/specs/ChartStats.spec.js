import { mount } from '@vue/test-utils';
import { ref } from 'vue';
import ChartStats from '../ChartStats.vue';
import { useReportMetrics } from 'dashboard/composables/useReportMetrics';

vi.mock('dashboard/composables/useReportMetrics');

const trendClasses = key => {
  useReportMetrics.mockReturnValue({
    calculateTrend: () => 50,
    displayMetric: () => '3',
    isAverageMetricType: metricKey => metricKey === 'reply_time',
    fetchingStatus: ref('finished'),
  });
  const wrapper = mount(ChartStats, {
    props: { metric: { KEY: key, NAME: 'Metric', trend: 50 } },
  });
  return wrapper.find('span.font-medium').classes();
};

describe('ChartStats.vue', () => {
  it('shows more conversations as an improvement', () => {
    expect(trendClasses('conversations_count')).toContain('text-n-teal-10');
  });

  it('shows more conversations with no reply as a setback, like longer times', () => {
    expect(trendClasses('no_reply_conversations_count')).toContain(
      'text-n-ruby-9'
    );
    expect(trendClasses('reply_time')).toContain('text-n-ruby-9');
  });
});

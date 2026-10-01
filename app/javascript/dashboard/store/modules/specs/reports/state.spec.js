import reports from '../../reports';
import { METRIC_CHART } from 'dashboard/routes/dashboard/settings/reports/constants';

describe('reports state', () => {
  // A report page renders a chart for each metric before its data arrives
  it('starts every chart metric with no data and not fetching', () => {
    Object.keys(METRIC_CHART).forEach(metric => {
      expect(reports.state.accountReport.data[metric]).toEqual([]);
      expect(reports.state.accountReport.isFetching[metric]).toBe(false);
    });
  });
});

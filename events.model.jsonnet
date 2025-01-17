local common = import 'common.libsonnet';
local util = import 'util.libsonnet';
local target = std.extVar('schema');
local predefined = import './predefined.jsonnet';

local installRevenue = std.extVar('installRevenue');

local user_props = common.get_user_properties();
local in_app_purchase = predefined.in_app_purchase;
local common_dimensions_all = common.dimensions + common.generate_event_dimensions(in_app_purchase.properties);
local common_measures_all = common.measures + common.all_events_revenue_measures;

local common_dimensions = if (!installRevenue) then util.filter_object(function(k, dimension) !std.objectHas(dimension, 'category') || dimension.category != 'Revenue', common_dimensions_all) else common_dimensions_all;
local common_measures = if (!installRevenue) then util.filter_object(function(k, measure) !std.objectHas(measure, 'category') || measure.category != 'Revenue', common_measures_all) else common_measures_all;

{
  name: 'firebase_events',
  label: '[Firebase] All events',
  category: 'Firebase Events',
  measures: common_measures,
  mappings: common.mappings,
  relations: common.relations,
  sql: |||
    SELECT *, (1.0 * `user_ltv`.`revenue`) - coalesce(lag(`user_ltv`.`revenue`) over (PARTITION BY user_pseudo_id ORDER BY event_timestamp), 0) as ltv_increase FROM `%(project)s`.`%(dataset)s`.`events_*`
    {%% if partitioned %%} WHERE _TABLE_SUFFIX BETWEEN FORMAT_DATE("%%Y%%m%%d", DATE '{{date.start}}') and FORMAT_DATE("%%Y%%m%%d", DATE '{{date.end}}') {%% endif %%}
    %(intraday_query)s
  ||| % {
    project: target.database,
    dataset: target.schema,
    intraday_query: if std.extVar('intradayAnalytics') == true then
      |||
        UNION ALL
        SELECT * FROM `%(project)s`.`%(dataset)s`.`events_intraday_*`
        {%% if partitioned %%} WHERE _TABLE_SUFFIX BETWEEN FORMAT_DATE("%%Y%%m%%d", DATE '{{date.start}}') and FORMAT_DATE("%%Y%%m%%d", DATE '{{date.end}}') {%% endif %%}
      ||| % {
        project: target.database,
        dataset: target.schema,
      } else '',
  },
  dimensions: {
    event_name: {
      type: 'string',
      sql: '{{TABLE}}.`event_name`',
    },
  } + common.generate_user_dimensions(user_props) + common_dimensions,
}

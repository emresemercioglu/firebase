local util = import '.././util.libsonnet';
local common = import 'common.libsonnet';
local target = std.extVar('schema');

local user_props = common.get_user_properties();

local custom_measures = {
  average_revenue_per_user: {
    sql: '{{measure.revenue}}/{{measure.active_users}}',
    type: 'double',
  },
  average_revenue_per_new_user: {
    sql: '{{measure.revenue}}/{{measure.new_users}}',
    type: 'double',
  },
  average_revenue_per_returning_user: {
    sql: '{{measure.revenue}}/{{measure.returning_users}}',
    type: 'double',
  },
  paying_and_returning_user_ratio: {
    sql: '{{measure.paying_users}}/{{measure.returning_users}}',
    type: 'double',
  },
  paying_and_returning_users: {
    sql: '{{dimension.firebase_user_id}}',
    aggregation: 'countUnique',
    filters: [{ dimension: 'returning_user_id', operator: 'isSet', valueType: 'unknown' }, { dimension: 'is_paying', operator: 'is', value: true, valueType: 'boolean' }],
    type: 'double',
    hidden: true,
  },
  revenue_from_paying_users: {
    sql: '{{measure.paying_and_returning_users}}/{{measure.returning_users}}',
  },
};

local user_properties = std.foldl(function(a, b) a + b, std.map(function(attr) {
  ['user_' + attr.name]: {
    category: 'User Attribute',
    sql: '{{TABLE}}.`' + attr.name + '`',
    type: attr.type,
  },
}, user_props), {});

local embedded_event = common.predefined.in_app_purchase;
local event_params_jinja = std.map(function(prop)
  |||
    {%% if in_query.event_%(name)s %%}
      , CASE WHEN event_params.key = '%(prop_db)s' THEN event_params.value.%(value_type)s END as %(name)s
    {%% endif %%}
  ||| % prop, embedded_event.properties);

{
  name: 'firebase_events',
  measures: common.predefined.in_app_purchase.measures + common.measures + custom_measures,
  mappings: common.mappings,
  relations: common.relations,
  sql: |||
    SELECT *
    %(user_props)s
    %(event_params)s
    FROM `%(project)s`.`%(dataset)s`.`events_*`
    {%% if in_query.user_ %%} LEFT JOIN UNNEST(user_properties) as user_properties {%% endif %%}
    {%% if in_query.event_ %%} LEFT JOIN UNNEST(event_params) as event_params {%% endif %%}
    {%% if partitioned %%} WHERE _TABLE_SUFFIX BETWEEN FORMAT_DATE("%%Y%%m%%d", DATE '{{date.start}}') and FORMAT_DATE("%%Y%%m%%d", DATE '{{date.end}}') {%% endif %%}
  ||| % { user_props: std.join('\n', common.generate_jinja_for_user_properties(user_props)), project: target.database, dataset: target.schema, event_params: std.join('\n', event_params_jinja) },
  dimensions: common.dimensions + user_properties + std.foldl(function(a, b) a + b, std.map(function(attr) {
    ['event_' + attr.name]: {
      category: 'Event Attribute',
      sql: '{{TABLE}}.`' + attr.name + '`',
      type: attr.type,
    },
  }, embedded_event.properties), {}),
}

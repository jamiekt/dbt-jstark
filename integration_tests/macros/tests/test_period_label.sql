{% macro jstark_test_period_label(results) %}

  {% set d = modules.datetime.date %}

  {# --- week_label. W01 begins on the first `first_day_of_week` on or
         before Jan 1, so late-December weeks can belong to the next year. --- #}
  {% set week_cases = [
      [d(2021, 12, 20), 'Monday', '2021w52'],
      [d(2021, 12, 27), 'Monday', '2022w01'],
      [d(2020, 12, 28), 'Monday', '2021w01'],
      [d(2021, 1, 4),   'Monday', '2021w02'],
      [d(2021, 6, 7),   'Monday', '2021w24'],
      [d(2021, 12, 19), 'Sunday', '2021w52'],
      [d(2021, 12, 26), 'Sunday', '2022w01']
  ] %}
  {# A week starting on or after that year's W01 anchor belongs to the next year.
     For Sunday weeks: W01 of 2022 starts 2021-12-26, so 2021-12-19 is W52 of 2021,
     but 2021-12-26 is W01 of 2022. This boundary looks surprising but is by design. #}
  {% for case in week_cases %}
    {% do jstark_assert_equal(
        results,
        'week_label(' ~ jstark.date_string(case[0]) ~ ', ' ~ case[1] ~ ')',
        jstark.week_label(case[0], case[1]), case[2]
    ) %}
  {% endfor %}

  {# --- absolute_period_label, all as_at 2022-01-01, Monday weeks.
         Cross-checked against jstark's column_metadata at 51d9083, then
         lowercased with '-' replaced by '_to_'. --- #}
  {% set as_at = d(2022, 1, 1) %}
  {% set label_cases = [
      ['0d0',  '20220101'],
      ['1d1',  '20211231'],
      ['3d1',  '20211229_to_20211231'],
      ['1w1',  '2021w52'],
      ['52w0', '2021w01_to_2022w01'],
      ['0m0',  '2022jan'],
      ['3m1',  '2021oct_to_2021dec'],
      ['12m12','2021jan'],
      ['4q4',  '2021q1'],
      ['0q0',  '2022q1'],
      ['3q1',  '2021q2_to_2021q4'],
      ['1y1',  '2021'],
      ['0y0',  '2022'],
      ['2y1',  '2020_to_2021']
  ] %}
  {% for case in label_cases %}
    {% do jstark_assert_equal(
        results, 'absolute_period_label(' ~ case[0] ~ ')',
        jstark.absolute_period_label(
            jstark.parse_feature_period(case[0]), as_at, 'Monday'
        ),
        case[1]
    ) %}
  {% endfor %}

  {# --- public_column_name switches on use_absolute_periods --- #}
  {% set fp = jstark.parse_feature_period('3m1') %}
  {% do jstark_assert_equal(
      results, 'public_column_name relative',
      jstark.public_column_name('GrossSpend', fp, false, as_at, 'Monday'),
      'gross_spend_3m1'
  ) %}
  {% do jstark_assert_equal(
      results, 'public_column_name absolute',
      jstark.public_column_name('GrossSpend', fp, true, as_at, 'Monday'),
      'gross_spend_2021oct_to_2021dec'
  ) %}
  {% do jstark_assert_equal(
      results, 'public_column_name absolute with a unit-infix override',
      jstark.public_column_name('BasketPeriods', fp, true, as_at, 'Monday'),
      'basket_months_2021oct_to_2021dec'
  ) %}

{% endmacro %}

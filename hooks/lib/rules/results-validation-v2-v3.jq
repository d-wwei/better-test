def array_or_empty($value):
  if ($value | type) == "array" then $value else [] end;

def nonempty_string($value):
  (($value | type) == "string") and ($value | test("\\S"));

def trimmed_string($value):
  nonempty_string($value)
  and ($value == ($value | gsub("^\\s+|\\s+$"; "")));

def iso_timestamp($value):
  nonempty_string($value)
  and (
    $value
    | test(
        "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]+)?(Z|[+-][0-9]{2}:[0-9]{2})$"
      )
  );

def nonnegative_integer($value):
  (($value | type) == "number")
  and ($value | isnan | not)
  and ($value | isfinite)
  and ($value >= 0)
  and (($value | floor) == $value);

def finite_number($value):
  (($value | type) == "number")
  and ($value | isnan | not)
  and ($value | isfinite);

def absolute:
  if . < 0 then -. else . end;

def normalized($value):
  (($value // "") | tostring | ascii_downcase);

def pass_status($value):
  (normalized($value) | test("^pass([_-].+)?$"));

def fail_status($value):
  (normalized($value) == "fail")
  or (normalized($value) == "partial_fail")
  or (normalized($value) == "partial-fail");

def allowed_status($value):
  [
    "pass",
    "pass_with_caveat",
    "pass-with-caveat",
    "pass_known_legacy_behavior",
    "pass-known-legacy-behavior",
    "fail",
    "blocked",
    "skip",
    "excluded",
    "pending",
    "partial",
    "partial_fail",
    "partial-fail"
  ] | index(normalized($value)) != null;

def allowed_evidence_level($value):
  ["indirect", "direct", "binary", "confirmed", "proven"]
  | index($value) != null;

def direct_or_stronger($value):
  ["direct", "confirmed", "proven"]
  | index(normalized($value)) != null;

def allowed_gate_verdict($value):
  ["pass", "fail", "blocked", "skip"] | index($value) != null;

def allowed_dod_verdict($value):
  ["pass", "fail", "blocked", "not_applicable"]
  | index($value) != null;

def required_checks($package_type):
  if $package_type == "hotfix" then
    ["manifest-scope", "impacted-gates", "red-flag-scan", "smoke"]
  elif $package_type == "feature" then
    ["impact-scope", "impacted-gates", "red-flag-scan", "smoke"]
  elif $package_type == "rc" then
    ["all-gates", "dirty-recovery", "full-suite", "coverage-denominator", "l2-audit"]
  elif $package_type == "non-release" then
    ["target-objective"]
  else
    []
  end;

. as $root
| array_or_empty($root.items) as $items
| array_or_empty($root.gate_items) as $gates
| ($items | map(select(nonempty_string(.id)) | .id)) as $item_ids
| ($gates | map(select(nonempty_string(.gate_id)) | .gate_id)) as $gate_ids
| [
    $items[] as $item
    | array_or_empty($item.evidence_sources)[]
    | select(nonempty_string(.source_id))
    | {
        source_id: .source_id,
        item_id: $item.id,
        item_type: $item.type,
        item_status: $item.status,
        evidence_level: $item.evidence_level
      }
  ] as $source_bindings
| {
    total: ($items | length),
    passed: (
      $items
      | map(select(pass_status(.status)))
      | length
    ),
    failed: (
      $items
      | map(select(fail_status(.status)))
      | length
    ),
    blocked: (
      $items
      | map(select(normalized(.status) == "blocked"))
      | length
    ),
    skipped: (
      $items
      | map(select(normalized(.status) == "skip"))
      | length
    ),
    excluded: (
      $items
      | map(select(normalized(.status) == "excluded"))
      | length
    ),
    pending: (
      $items
      | map(select(normalized(.status) == "pending"))
      | length
    ),
    partial: (
      $items
      | map(select(normalized(.status) == "partial"))
      | length
    )
  } as $actual_summary
| [
    (
      select(
        (($root.schema_version | type) != "number")
        or (($root.schema_version | floor) != $root.schema_version)
        or (
          ($root.schema_version != 2)
          and ($root.schema_version != 3)
        )
      )
      | "- schema_version 必须是整数 2 或 3，不能使用字符串或布尔值"
    ),
    (
      ["version", "tester_id", "run_id", "mode"][]
      | . as $field
      | select(nonempty_string($root[$field]) | not)
      | "- schema v\($root.schema_version) 顶层字段 \($field) 必须是非空字符串"
    ),
    (
      select(iso_timestamp($root.finished_at) | not)
      | "- schema v\($root.schema_version) finished_at 必须是带时区的 ISO 8601 时间"
    ),
    (
      select(($root.schema_version | tostring) == "3")
      | select(iso_timestamp($root.started_at) | not)
      | "- schema v3 started_at 必须是带时区的 ISO 8601 时间"
    ),

    # Every v2/v3 item has an unambiguous identity and evidence grade.
    (
      select(($root.schema_version | tostring) == "3")
      | select(($items | length) == 0)
      | "- schema v3 items 不得为空；零用例 run 不能形成有效结论"
    ),
    (
      $items[]
      | select(nonempty_string(.id) | not)
      | "- item 缺少非空 id"
    ),
    (
      $items[]
      | select(
          nonempty_string(.id)
          and ((.id | test("^[A-Z][A-Z0-9]*([.-][A-Z0-9]+)+$")) | not)
        )
      | "- item id 格式不合法: \(.id)"
    ),
    (
      $item_ids
      | group_by(.)
      | .[]
      | select(length > 1)
      | "- item id 重复: \(.[0])"
    ),
    (
      $items[]
      | select(nonempty_string(.evidence_level) | not)
      | "- item \(.id // "<missing-id>") 缺少 evidence_level"
    ),
    (
      $items[]
      | select(
          nonempty_string(.evidence_level)
          and (allowed_evidence_level(.evidence_level) | not)
        )
      | "- item \(.id // "<missing-id>") 的 evidence_level 不支持: \(.evidence_level)"
    ),
    (
      $items[]
      | select(allowed_status(.status) | not)
      | "- item \(.id // "<missing-id>") 的 status 不支持或缺失: \(.status // "<missing-status>")"
    ),
    (
      select(($root.schema_version | tostring) == "3")
      | $items[]
      | select(
          (normalized(.status) == "skip" or normalized(.status) == "excluded")
          and (nonempty_string(.skip_reason) | not)
        )
      | "- schema v3 item \(.id // "<missing-id>") 为 skip/excluded 时必须提供非空 skip_reason"
    ),
    (
      select(($root.schema_version | tostring) == "3")
      | $items[]
      | select(
          (
            normalized(.status) == "pass_with_caveat"
            or normalized(.status) == "pass-with-caveat"
            or normalized(.status) == "pass_known_legacy_behavior"
            or normalized(.status) == "pass-known-legacy-behavior"
          )
          and (nonempty_string(.caveat_reason) | not)
        )
      | "- schema v3 caveat/known-legacy pass item \(.id // "<missing-id>") 必须提供 caveat_reason"
    ),
    (
      select(($root.schema_version | tostring) == "3")
      | $items[]
      | select(
          (
            normalized(.status) == "pass_known_legacy_behavior"
            or normalized(.status) == "pass-known-legacy-behavior"
          )
          and .pre_existing != true
        )
      | "- schema v3 pass_known_legacy_behavior item \(.id // "<missing-id>") 必须设置 pre_existing=true"
    ),
    (
      select(($root.schema_version | tostring) == "3")
      | $items[] as $item
      | select(
          ["functional", "metadata"]
          | index(normalized($item.type)) == null
        )
      | "- schema v3 item \($item.id // "<missing-id>") 的 type 必须是 functional|metadata"
    ),
    (
      select(($root.schema_version | tostring) == "3")
      | $items[]
      | select(
          pass_status(.status)
          and (nonempty_string(.assertion_field) | not)
        )
      | "- schema v3 pass item \(.id // "<missing-id>") 的 assertion_field 必须是非空字符串"
    ),
    (
      select(($root.schema_version | tostring) == "3")
      | $items[]
      | select(
          pass_status(.status)
          and (
            (.assertion_value == null)
            or (
              (.assertion_value | type) == "string"
              and (nonempty_string(.assertion_value) | not)
            )
          )
        )
      | "- schema v3 pass item \(.id // "<missing-id>") 必须包含非空 assertion_value"
    ),
    (
      select(($root.schema_version | tostring) == "3")
      | select(normalized($root.mode) | test("compare"))
      | $items[]
      | select(
          pass_status(.status)
          and (nonempty_string(.comparison_baseline) | not)
        )
      | "- schema v3 compare 模式的 pass item \(.id // "<missing-id>") 必须提供 comparison_baseline"
    ),
    (
      select(($root.schema_version | tostring) == "3")
      | select((normalized($root.mode) | test("bug-retest")) | not)
      | $items[]
      | select(pass_status(.status) and .pre_existing == true)
      | "- schema v3 非 bug-retest 模式的 pre_existing item \(.id // "<missing-id>") 不得标 pass"
    ),
    (
      select(($root.schema_version | tostring) == "3")
      | $items[]
      | select(
          normalized(.type) == "functional"
          and (pass_status(.status) or fail_status(.status))
          and normalized(.evidence_level) == "binary"
        )
      | "- schema v3 functional item \(.id // "<missing-id>") 的 pass/fail 不能只使用 binary evidence"
    ),

    # Summary and coverage are arithmetic evidence, not free-form claims.
    (
      select(($root.summary | type) != "object")
      | "- schema v\($root.schema_version) summary 必须是对象"
    ),
    (
      ["total", "passed", "failed", "blocked", "skipped", "excluded", "pending", "partial"][]
      | . as $field
      | select(nonnegative_integer($root.summary[$field]) | not)
      | "- schema v\($root.schema_version) summary.\($field) 必须是非负整数"
    ),
    (
      ["total", "passed", "failed", "blocked", "skipped", "excluded", "pending", "partial"][]
      | . as $field
      | select(
          nonnegative_integer($root.summary[$field])
          and ($root.summary[$field] != $actual_summary[$field])
        )
      | "- schema v\($root.schema_version) summary.\($field)=\($root.summary[$field]) 与 items 实际计数 \($actual_summary[$field]) 不一致"
    ),
    (
      select(($root.schema_version | tostring) == "3")
      | select(($root.coverage | type) != "object")
      | "- schema v3 coverage 必须是对象"
    ),
    (
      select(($root.schema_version | tostring) == "3")
      | ["manifest_total", "unreachable", "reachable", "tested"][]
      | . as $field
      | select(nonnegative_integer($root.coverage[$field]) | not)
      | "- schema v3 coverage.\($field) 必须是非负整数"
    ),
    (
      select(($root.schema_version | tostring) == "3")
      | select(
          (finite_number($root.coverage.reachable_coverage_pct) | not)
          or ($root.coverage.reachable_coverage_pct < 0)
          or ($root.coverage.reachable_coverage_pct > 100)
        )
      | "- schema v3 coverage.reachable_coverage_pct 必须是 0 到 100 的数字"
    ),
    (
      select(($root.schema_version | tostring) == "3")
      | select(
          nonnegative_integer($root.coverage.manifest_total)
          and nonnegative_integer($root.coverage.unreachable)
          and nonnegative_integer($root.coverage.reachable)
          and (
            $root.coverage.manifest_total
            != ($root.coverage.unreachable + $root.coverage.reachable)
          )
        )
      | "- schema v3 coverage.manifest_total 必须等于 unreachable + reachable"
    ),
    (
      select(($root.schema_version | tostring) == "3")
      | select(
          nonnegative_integer($root.coverage.tested)
          and nonnegative_integer($root.coverage.reachable)
          and ($root.coverage.tested > $root.coverage.reachable)
        )
      | "- schema v3 coverage.tested 不得大于 reachable"
    ),
    (
      select(($root.schema_version | tostring) == "3")
      | select(
          nonnegative_integer($root.coverage.tested)
          and ($root.coverage.tested > ($items | length))
        )
      | "- schema v3 coverage.tested 不得大于 items 数量"
    ),
    (
      select(($root.schema_version | tostring) == "3")
      | select(
          nonnegative_integer($root.coverage.tested)
          and nonnegative_integer($root.coverage.reachable)
          and finite_number($root.coverage.reachable_coverage_pct)
          and (
            (
              $root.coverage.reachable_coverage_pct
              - (
                  if $root.coverage.reachable == 0 then
                    0
                  else
                    (100 * $root.coverage.tested / $root.coverage.reachable)
                  end
                )
            )
            | absolute
          ) > 0.01
        )
      | "- schema v3 coverage.reachable_coverage_pct 与 tested/reachable 计算不一致"
    ),

    # Gate ledger integrity shared by v2 and v3.
    (
      $gates[]
      | select(nonempty_string(.gate_id) | not)
      | "- gate_items 项缺少非空 gate_id"
    ),
    (
      $gates[]
      | select(
          nonempty_string(.gate_id)
          and ((.gate_id | test("^[A-Z][A-Z0-9]*([.-][A-Z0-9]+)+$")) | not)
        )
      | "- gate_id 格式不合法: \(.gate_id)"
    ),
    (
      $gate_ids
      | group_by(.)
      | .[]
      | select(length > 1)
      | "- gate_id 重复: \(.[0])"
    ),
    (
      $gates[]
      | select(nonempty_string(.verdict) | not)
      | "- gate \(.gate_id // "<missing-gate-id>") 缺少 verdict"
    ),
    (
      $gates[]
      | select(nonempty_string(.verdict) and (allowed_gate_verdict(.verdict) | not))
      | "- gate \(.gate_id // "<missing-gate-id>") 的 verdict 不支持: \(.verdict)"
    ),
    (
      $gates[]
      | select(nonempty_string(.reason) | not)
      | "- gate \(.gate_id // "<missing-gate-id>") 缺少非空 reason"
    ),
    (
      $gates[]
      | select((.item_ids | type) != "array" or ((.item_ids | length) == 0))
      | "- gate \(.gate_id // "<missing-gate-id>") 的 item_ids 必须是非空数组"
    ),
    (
      $gates[]
      | select(
          (.item_ids | type) == "array"
          and ((.item_ids | unique | length) != (.item_ids | length))
        )
      | "- gate \(.gate_id // "<missing-gate-id>") 的 item_ids 不得重复"
    ),
    (
      $gates[] as $gate
      | array_or_empty($gate.item_ids)[]
      | . as $item_id
      | select(($item_ids | index($item_id)) == null)
      | "- gate \($gate.gate_id // "<missing-gate-id>") 引用了不存在的 item: \($item_id)"
    ),
    (
      $gates[] as $gate
      | [
          array_or_empty($gate.item_ids)[] as $item_id
          | $items[]
          | select(.id == $item_id)
          | normalized(.status)
        ] as $statuses
      | select(
          normalized($gate.verdict) == "pass"
          and (
            ($statuses | length) == 0
            or ($statuses | all(pass_status(.)) | not)
          )
        )
      | "- gate \($gate.gate_id // "<missing-gate-id>") verdict=pass 只能引用 pass 类 item"
    ),
    (
      $gates[] as $gate
      | [
          array_or_empty($gate.item_ids)[] as $item_id
          | $items[]
          | select(.id == $item_id)
          | normalized(.status)
        ] as $statuses
      | select(
          normalized($gate.verdict) == "fail"
          and ($statuses | any(fail_status(.)) | not)
        )
      | "- gate \($gate.gate_id // "<missing-gate-id>") verdict=fail 至少要引用一个 fail/partial_fail item"
    ),
    (
      $gates[] as $gate
      | [
          array_or_empty($gate.item_ids)[] as $item_id
          | $items[]
          | select(.id == $item_id)
          | normalized(.status)
        ] as $statuses
      | select(
          normalized($gate.verdict) == "blocked"
          and ($statuses | any(. == "blocked" or . == "pending") | not)
        )
      | "- gate \($gate.gate_id // "<missing-gate-id>") verdict=blocked 至少要引用一个 blocked/pending item"
    ),
    (
      $gates[] as $gate
      | [
          array_or_empty($gate.item_ids)[] as $item_id
          | $items[]
          | select(.id == $item_id)
          | normalized(.status)
        ] as $statuses
      | select(
          normalized($gate.verdict) == "skip"
          and (
            ($statuses | length) == 0
            or ($statuses | all(. == "skip" or . == "excluded") | not)
          )
        )
      | "- gate \($gate.gate_id // "<missing-gate-id>") verdict=skip 只能引用 skip/excluded item"
    ),

    # v3 binds the run to an environment and makes evidence independently traceable.
    (
      select(($root.schema_version | tostring) == "3")
      | select(
          ["hotfix", "feature", "rc", "non-release"]
          | index($root.package_type) == null
      )
      | "- schema v3 package_type 必须是 hotfix|feature|rc|non-release"
    ),
    (
      select(($root.schema_version | tostring) == "3")
      | select(
          ["required", "none"]
          | index($root.gate_applicability) == null
        )
      | "- schema v3 gate_applicability 必须是 required|none"
    ),
    (
      select(($root.schema_version | tostring) == "3")
      | select(
          $root.gate_applicability == "required"
          and ($gates | length) == 0
        )
      | "- schema v3 gate_applicability=required 时 gate_items 不得为空"
    ),
    (
      select(($root.schema_version | tostring) == "3")
      | select(
          $root.gate_applicability == "none"
          and ($gates | length) != 0
        )
      | "- schema v3 gate_applicability=none 时 gate_items 必须为空"
    ),
    (
      select(($root.schema_version | tostring) == "3")
      | select(
          $root.gate_applicability == "none"
          and (nonempty_string($root.gate_applicability_reason) | not)
        )
      | "- schema v3 gate_applicability=none 时必须提供 gate_applicability_reason"
    ),
    (
      select(($root.schema_version | tostring) == "3")
      | select(($root.environment | type) != "object")
      | "- schema v3 environment 必须是对象"
    ),
    (
      select(($root.schema_version | tostring) == "3")
      | ["environment_id", "machine_id", "config_profile"][]
      | . as $field
      | select(trimmed_string($root.environment[$field]) | not)
      | "- schema v3 environment.\($field) 必须是无首尾空白的非空字符串"
    ),
    (
      select(($root.schema_version | tostring) == "3")
      | $items[]
      | select((.evidence_sources | type) != "array" or ((.evidence_sources | length) == 0))
      | "- schema v3 item \(.id // "<missing-id>") 的 evidence_sources 必须是非空数组"
    ),
    (
      select(($root.schema_version | tostring) == "3")
      | $items[] as $item
      | array_or_empty($item.evidence_sources)[]
      | . as $source
      | ["source_id", "independence_key", "artifact_ref"][]
      | . as $field
      | select(trimmed_string($source[$field]) | not)
      | "- schema v3 item \($item.id // "<missing-id>") 的 evidence source 缺少无首尾空白的 \($field)"
    ),
    (
      select(($root.schema_version | tostring) == "3")
      | $items[] as $item
      | array_or_empty($item.evidence_sources)[]
      | select(
          nonempty_string(.source_id)
          and ((.source_id | test("^[A-Z][A-Z0-9]*([.-][A-Z0-9]+)+$")) | not)
        )
      | "- schema v3 item \($item.id // "<missing-id>") 的 evidence source_id 格式不合法: \(.source_id)"
    ),
    (
      select(($root.schema_version | tostring) == "3")
      | [
          $items[]
          | array_or_empty(.evidence_sources)[]
          | select(nonempty_string(.source_id))
          | .source_id
        ]
      | group_by(.)
      | .[]
      | select(length > 1)
      | "- schema v3 evidence source_id 全 run 重复: \(.[0])"
    ),
    (
      select(($root.schema_version | tostring) == "3")
      | $items[]
      | select(
          normalized(.evidence_level) == "indirect"
          and (pass_status(.status) or fail_status(.status))
        )
      | "- schema v3 item \(.id // "<missing-id>") 为 pass/fail 时 evidence_level 不得为 indirect"
    ),
    (
      select(($root.schema_version | tostring) == "3")
      | $items[] as $item
      | select(normalized($item.evidence_level) == "confirmed")
      | [
          array_or_empty($item.evidence_sources)[]
          | select(nonempty_string(.independence_key))
          | (.independence_key | gsub("^\\s+|\\s+$"; ""))
        ]
      | unique
      | select(length < 2)
      | "- schema v3 confirmed item \($item.id // "<missing-id>") 需要至少两个不同 independence_key 的 evidence_sources"
    ),
    (
      select(($root.schema_version | tostring) == "3")
      | $items[] as $item
      | select(normalized($item.evidence_level) == "confirmed")
      | [
          array_or_empty($item.evidence_sources)[]
          | select(nonempty_string(.artifact_ref))
          | (.artifact_ref | gsub("^\\s+|\\s+$"; ""))
        ]
      | unique
      | select(length < 2)
      | "- schema v3 confirmed item \($item.id // "<missing-id>") 需要至少两个不同 artifact_ref，不能重复引用同一证据"
    ),
    (
      select(($root.schema_version | tostring) == "3")
      | $items[] as $item
      | select(normalized($item.evidence_level) == "proven")
      | select(($item.proven_basis | type) != "object")
      | "- schema v3 proven item \($item.id // "<missing-id>") 必须提供 proven_basis"
    ),
    (
      select(($root.schema_version | tostring) == "3")
      | $items[] as $item
      | select(normalized($item.evidence_level) == "proven")
      | select(
          ["source", "proto", "multi-version"]
          | index($item.proven_basis.kind) == null
        )
      | "- schema v3 proven item \($item.id // "<missing-id>") 的 proven_basis.kind 必须是 source|proto|multi-version"
    ),
    (
      select(($root.schema_version | tostring) == "3")
      | $items[] as $item
      | select(normalized($item.evidence_level) == "proven")
      | select(
          ($item.proven_basis.evidence_refs | type) != "array"
          or (($item.proven_basis.evidence_refs | length) == 0)
      )
      | "- schema v3 proven item \($item.id // "<missing-id>") 的 proven_basis.evidence_refs 必须是非空数组"
    ),
    (
      select(($root.schema_version | tostring) == "3")
      | $items[] as $item
      | select(normalized($item.evidence_level) == "proven")
      | select(
          ($item.proven_basis.evidence_refs | type) == "array"
          and (
            ($item.proven_basis.evidence_refs | unique | length)
            != ($item.proven_basis.evidence_refs | length)
          )
        )
      | "- schema v3 proven item \($item.id // "<missing-id>") 的 proven_basis.evidence_refs 不得重复"
    ),
    (
      select(($root.schema_version | tostring) == "3")
      | $items[] as $item
      | select(normalized($item.evidence_level) == "proven")
      | array_or_empty($item.proven_basis.evidence_refs)[] as $source_id
      | select(
          (
            array_or_empty($item.evidence_sources)
            | map(.source_id)
            | index($source_id)
          ) == null
        )
      | "- schema v3 proven item \($item.id // "<missing-id>") 引用了不存在的 evidence source: \($source_id)"
    ),
    (
      select(($root.schema_version | tostring) == "3")
      | $items[] as $item
      | select(
          normalized($item.evidence_level) == "proven"
          and (
            $item.proven_basis.kind == "source"
            or $item.proven_basis.kind == "proto"
          )
        )
      | select(
          (
            array_or_empty($item.proven_basis.evidence_refs) as $basis_refs
            | array_or_empty($item.evidence_sources)
            | map(
                . as $source
                | select(
                    ($basis_refs | index($source.source_id)) != null
                    and normalized($source.evidence_kind)
                      == $item.proven_basis.kind
                  )
              )
            | length
          ) == 0
        )
      | "- schema v3 proven item \($item.id // "<missing-id>") 的 source/proto basis 必须引用匹配 evidence_kind 的 source"
    ),
    (
      select(($root.schema_version | tostring) == "3")
      | $items[] as $item
      | select(
          normalized($item.evidence_level) == "proven"
          and $item.proven_basis.kind == "multi-version"
        )
      | select(
          (array_or_empty($item.proven_basis.evidence_refs) | unique | length) < 2
          or ($item.proven_basis.versions | type) != "array"
          or (
            array_or_empty($item.proven_basis.versions)
            | map(select(trimmed_string(.) ))
            | unique
            | length
          ) < 2
        )
      | "- schema v3 proven item \($item.id // "<missing-id>") 的 multi-version basis 至少需要两个 evidence refs 和两个版本"
    ),
    (
      select(($root.schema_version | tostring) == "3")
      | $items[] as $item
      | select(
          normalized($item.evidence_level) == "proven"
          and $item.proven_basis.kind == "multi-version"
        )
      | (
          array_or_empty($item.proven_basis.evidence_refs) as $basis_refs
          | [
              array_or_empty($item.evidence_sources)[] as $source
              | select(($basis_refs | index($source.source_id)) != null)
              | {
                  kind: normalized($source.evidence_kind),
                  version: ($source.version // "")
                }
            ]
        ) as $basis_sources
      | select(
          ($basis_sources | length)
            != (array_or_empty($item.proven_basis.evidence_refs) | length)
          or ($basis_sources | any(.kind != "binary"))
          or (
            ($basis_sources | map(.version) | sort | unique)
            != (
              array_or_empty($item.proven_basis.versions)
              | sort
              | unique
            )
          )
      )
      | "- schema v3 proven item \($item.id // "<missing-id>") 的 multi-version refs 必须是 binary evidence，且 version 集合与 proven_basis.versions 一致"
    ),
    (
      select(($root.schema_version | tostring) == "3")
      | $items[] as $item
      | select(
          normalized($item.evidence_level) == "proven"
          and normalized($item.type) == "functional"
          and (pass_status($item.status) or fail_status($item.status))
        )
      | select(
          ($item.proven_basis.runtime_evidence_refs | type) != "array"
          or (($item.proven_basis.runtime_evidence_refs | length) == 0)
        )
      | "- schema v3 proven functional item \($item.id // "<missing-id>") 必须提供 runtime_evidence_refs"
    ),
    (
      select(($root.schema_version | tostring) == "3")
      | $items[] as $item
      | select(
          normalized($item.evidence_level) == "proven"
          and normalized($item.type) == "functional"
          and (pass_status($item.status) or fail_status($item.status))
        )
      | array_or_empty($item.proven_basis.runtime_evidence_refs)[] as $source_id
      | select(
          (
            array_or_empty($item.evidence_sources)
            | map(
                . as $source
                | select(
                    $source.source_id == $source_id
                    and normalized($source.evidence_kind) == "runtime"
                  )
              )
            | length
          ) == 0
        )
      | "- schema v3 proven functional item \($item.id // "<missing-id>") 的 runtime_evidence_refs 必须引用 evidence_kind=runtime 的本 item source"
    ),
    (
      select(($root.schema_version | tostring) == "3")
      | $gates[]
      | select((.evidence_refs | type) != "array" or ((.evidence_refs | length) == 0))
      | "- schema v3 gate \(.gate_id // "<missing-gate-id>") 的 evidence_refs 必须是非空数组"
    ),
    (
      select(($root.schema_version | tostring) == "3")
      | $gates[]
      | select(
          (.evidence_refs | type) == "array"
          and ((.evidence_refs | unique | length) != (.evidence_refs | length))
        )
      | "- schema v3 gate \(.gate_id // "<missing-gate-id>") 的 evidence_refs 不得重复"
    ),
    (
      select(($root.schema_version | tostring) == "3")
      | [
          $items[]
          | array_or_empty(.evidence_sources)[]
          | select(nonempty_string(.source_id))
          | .source_id
        ] as $source_ids
      | $gates[] as $gate
      | array_or_empty($gate.evidence_refs)[]
      | . as $source_id
      | select(($source_ids | index($source_id)) == null)
      | "- schema v3 gate \($gate.gate_id // "<missing-gate-id>") 引用了不存在的 evidence source: \($source_id)"
    ),
    (
      select(($root.schema_version | tostring) == "3")
      | $gates[] as $gate
      | array_or_empty($gate.evidence_refs)[]
      | . as $source_id
      | select(
          (
            $source_bindings
            | map(
                . as $binding
                | select(
                  $binding.source_id == $source_id
                  and (
                    array_or_empty($gate.item_ids)
                    | index($binding.item_id) != null
                  )
                )
              )
            | length
          ) == 0
        )
      | "- schema v3 gate \($gate.gate_id // "<missing-gate-id>") 的 evidence source \($source_id) 不属于该 gate 的 item_ids"
    ),

    # v3 DoD ledger and release-readiness closure.
    (
      select(($root.schema_version | tostring) == "3")
      | select(($root.dod | type) != "object")
      | "- schema v3 dod 必须是对象"
    ),
    (
      select(($root.schema_version | tostring) == "3")
      | select(allowed_dod_verdict($root.dod.verdict) | not)
      | "- schema v3 dod.verdict 必须是 pass|fail|blocked|not_applicable"
    ),
    (
      select(($root.schema_version | tostring) == "3")
      | select(($root.dod.check_results | type) != "array")
      | "- schema v3 dod.check_results 必须是数组"
    ),
    (
      select(($root.schema_version | tostring) == "3")
      | array_or_empty($root.dod.check_results)[]
      | select(nonempty_string(.check_id) | not)
      | "- schema v3 DoD check 缺少非空 check_id"
    ),
    (
      select(($root.schema_version | tostring) == "3")
      | [
          array_or_empty($root.dod.check_results)[]
          | select(nonempty_string(.check_id))
          | .check_id
        ]
      | group_by(.)
      | .[]
      | select(length > 1)
      | "- schema v3 DoD check_id 重复: \(.[0])"
    ),
    (
      select(($root.schema_version | tostring) == "3")
      | array_or_empty($root.dod.check_results)[]
      | select(allowed_dod_verdict(.verdict) | not)
      | "- schema v3 DoD check \(.check_id // "<missing-check-id>") verdict 不合法"
    ),
    (
      select(($root.schema_version | tostring) == "3")
      | array_or_empty($root.dod.check_results)[]
      | select(nonempty_string(.reason) | not)
      | "- schema v3 DoD check \(.check_id // "<missing-check-id>") 缺少非空 reason"
    ),
    (
      select(($root.schema_version | tostring) == "3")
      | array_or_empty($root.dod.check_results)[]
      | select(
          (.item_ids | type) != "array"
          or (.gate_ids | type) != "array"
          or (
            has("evidence_refs")
            and ((.evidence_refs | type) != "array")
          )
        )
      | "- schema v3 DoD check \(.check_id // "<missing-check-id>") 的 item_ids/gate_ids/evidence_refs 必须是数组"
    ),
    (
      select(($root.schema_version | tostring) == "3")
      | array_or_empty($root.dod.check_results)[]
      | select(
          (.item_ids | type) == "array"
          and (.gate_ids | type) == "array"
          and ((.item_ids | length) == 0)
          and ((.gate_ids | length) == 0)
          and ((array_or_empty(.evidence_refs) | length) == 0)
        )
      | "- schema v3 DoD check \(.check_id // "<missing-check-id>") 必须至少引用一个 item、gate 或 evidence source"
    ),
    (
      select(($root.schema_version | tostring) == "3")
      | array_or_empty($root.dod.check_results)[] as $check
      | array_or_empty($check.item_ids)[]
      | . as $item_id
      | select(($item_ids | index($item_id)) == null)
      | "- schema v3 DoD check \($check.check_id // "<missing-check-id>") 引用了不存在的 item: \($item_id)"
    ),
    (
      select(($root.schema_version | tostring) == "3")
      | array_or_empty($root.dod.check_results)[] as $check
      | array_or_empty($check.gate_ids)[]
      | . as $gate_id
      | select(($gate_ids | index($gate_id)) == null)
      | "- schema v3 DoD check \($check.check_id // "<missing-check-id>") 引用了不存在的 gate: \($gate_id)"
    ),
    (
      select(($root.schema_version | tostring) == "3")
      | [
          $source_bindings[]
          | .source_id
        ] as $source_ids
      | array_or_empty($root.dod.check_results)[] as $check
      | array_or_empty($check.evidence_refs)[]
      | . as $source_id
      | select(($source_ids | index($source_id)) == null)
      | "- schema v3 DoD check \($check.check_id // "<missing-check-id>") 引用了不存在的 evidence source: \($source_id)"
    ),
    (
      select(($root.schema_version | tostring) == "3")
      | array_or_empty($root.dod.check_results)[] as $check
      | select(
          ["smoke", "dirty-recovery", "full-suite"]
          | index($check.check_id) != null
        )
      | select(
          (
            array_or_empty($check.item_ids) as $check_item_ids
            | $items
            | map(
                . as $candidate
                |
                select(
                  ($check_item_ids | index($candidate.id)) != null
                  and normalized($candidate.type) == "functional"
                  and pass_status($candidate.status)
                  and direct_or_stronger($candidate.evidence_level)
                )
              )
            | length
          ) == 0
        )
      | "- schema v3 DoD check \($check.check_id) 必须引用至少一个 direct+ 的 functional pass item"
    ),
    (
      select(($root.schema_version | tostring) == "3")
      | array_or_empty($root.dod.check_results)[] as $check
      | select(
          ["red-flag-scan", "coverage-denominator", "l2-audit"]
          | index($check.check_id) != null
        )
      | select(
          (
            array_or_empty($check.evidence_refs) as $evidence_refs
            | $source_bindings
            | map(
                . as $binding
                |
                select(
                  ($evidence_refs | index($binding.source_id)) != null
                  and direct_or_stronger($binding.evidence_level)
                )
              )
            | length
          ) == 0
      )
      | "- schema v3 DoD check \($check.check_id) 必须引用至少一个 direct+ evidence source"
    ),
    (
      select(($root.schema_version | tostring) == "3")
      | select($root.gate_applicability == "required")
      | array_or_empty($root.dod.check_results)[] as $check
      | select(
          ["impacted-gates", "all-gates"]
          | index($check.check_id) != null
        )
      | select((array_or_empty($check.gate_ids) | length) == 0)
      | "- schema v3 gate_applicability=required 时 DoD check \($check.check_id) 必须引用 gate"
    ),
    (
      select(($root.schema_version | tostring) == "3")
      | select($root.gate_applicability == "required")
      | array_or_empty($root.dod.check_results)[] as $check
      | select(
          ["impacted-gates", "all-gates"]
          | index($check.check_id) != null
        )
      | select(
          (array_or_empty($check.gate_ids) | sort | unique)
          != ($gate_ids | sort | unique)
        )
      | "- schema v3 DoD check \($check.check_id) 必须覆盖 gate_items 中全部适用 gate"
    ),
    (
      select(($root.schema_version | tostring) == "3")
      | select($root.gate_applicability == "required")
      | array_or_empty($root.dod.check_results)[] as $check
      | select(
          ["impacted-gates", "all-gates"]
          | index($check.check_id) != null
        )
      | array_or_empty($check.gate_ids)[] as $check_gate_id
      | $gates[]
      | select(.gate_id == $check_gate_id and normalized(.verdict) != "pass")
      | "- schema v3 DoD check \($check.check_id) 引用的 gate \($check_gate_id) 必须 pass"
    ),
    (
      select(($root.schema_version | tostring) == "3")
      | required_checks($root.package_type)[]
      | . as $required_check
      | select(
          (
            array_or_empty($root.dod.check_results)
            | map(.check_id)
            | index($required_check)
          ) == null
        )
      | "- schema v3 \(($root.package_type // "<missing-package-type>")) DoD 缺少 required check: \($required_check)"
    ),
    (
      select(($root.schema_version | tostring) == "3")
      | select(normalized($root.dod.verdict) == "pass")
      | required_checks($root.package_type)[]
      | . as $required_check
      | (
          array_or_empty($root.dod.check_results)
          | map(select(.check_id == $required_check))
          | .[0].verdict
        ) as $check_verdict
      | select(normalized($check_verdict) != "pass")
      | "- schema v3 dod.verdict=pass 时 required check \($required_check) 必须 pass"
    ),
    (
      select(($root.schema_version | tostring) == "3")
      | select(normalized($root.dod.verdict) == "pass")
      | array_or_empty($root.dod.check_results)[]
      | select(normalized(.verdict) != "pass")
      | "- schema v3 dod.verdict=pass 时所有 DoD check 都必须 pass，发现 \(.check_id // "<missing-check-id>")=\(.verdict // "<missing-verdict>")"
    ),
    (
      select(($root.schema_version | tostring) == "3")
      | select(normalized($root.dod.verdict) == "fail")
      | select(
          array_or_empty($root.dod.check_results)
          | any(normalized(.verdict) == "fail")
          | not
        )
      | "- schema v3 dod.verdict=fail 至少需要一个 fail check"
    ),
    (
      select(($root.schema_version | tostring) == "3")
      | select(normalized($root.dod.verdict) == "blocked")
      | select(
          array_or_empty($root.dod.check_results)
          | any(normalized(.verdict) == "blocked")
          | not
        )
      | "- schema v3 dod.verdict=blocked 至少需要一个 blocked check"
    ),
    (
      select(($root.schema_version | tostring) == "3")
      | select(($root.release_readiness | type) != "object")
      | "- schema v3 release_readiness 必须是对象"
    ),
    (
      select(($root.schema_version | tostring) == "3")
      | select(
          ["go", "no-go", "blocked", "not_applicable"]
          | index($root.release_readiness.verdict) == null
        )
      | "- schema v3 release_readiness.verdict 必须是 go|no-go|blocked|not_applicable"
    ),
    (
      select(($root.schema_version | tostring) == "3")
      | select(
          normalized($root.release_readiness.verdict) == "go"
          and normalized($root.dod.verdict) != "pass"
      )
      | "- schema v3 release_readiness=go 要求 dod.verdict=pass"
    ),
    (
      select(($root.schema_version | tostring) == "3")
      | select(normalized($root.release_readiness.verdict) == "go")
      | select(($items | any(pass_status(.status))) | not)
      | "- schema v3 release_readiness=go 至少需要一个 pass 类 item"
    ),
    (
      select(($root.schema_version | tostring) == "3")
      | select(normalized($root.release_readiness.verdict) == "go")
      | $items[]
      | select(
          normalized(.status) == "fail"
          or normalized(.status) == "blocked"
          or normalized(.status) == "pending"
          or normalized(.status) == "partial"
          or normalized(.status) == "partial_fail"
          or normalized(.status) == "partial-fail"
        )
      | "- schema v3 release_readiness=go 不允许 item \(.id // "<missing-id>") 为 \(.status)"
    ),
    (
      select(($root.schema_version | tostring) == "3")
      | select(normalized($root.release_readiness.verdict) == "go")
      | select(
          (nonnegative_integer($root.coverage.tested) | not)
          or ($root.coverage.tested == 0)
        )
      | "- schema v3 release_readiness=go 要求 coverage.tested > 0"
    ),
    (
      select(($root.schema_version | tostring) == "3")
      | select(normalized($root.release_readiness.verdict) == "go")
      | $gates[]
      | select(normalized(.verdict) == "fail" or normalized(.verdict) == "blocked")
      | "- schema v3 release_readiness=go 不允许 gate \(.gate_id // "<missing-gate-id>") 为 \(.verdict)"
    ),
    (
      select(($root.schema_version | tostring) == "3")
      | select(normalized($root.release_readiness.verdict) == "go")
      | select(
          ($gates | any(normalized(.verdict) == "skip"))
          or (
            nonnegative_integer($root.coverage.tested)
            and nonnegative_integer($root.coverage.reachable)
            and ($root.coverage.tested < $root.coverage.reachable)
          )
          or (
            $items
            | any(
                normalized(.status) == "skip"
                or normalized(.status) == "excluded"
                or normalized(.status) == "pass_with_caveat"
                or normalized(.status) == "pass-with-caveat"
                or normalized(.status) == "pass_known_legacy_behavior"
                or normalized(.status) == "pass-known-legacy-behavior"
              )
          )
        )
      | select(
          ($root.release_readiness.override | type) != "object"
          or (trimmed_string($root.release_readiness.override.approved_by) | not)
          or (iso_timestamp($root.release_readiness.override.approved_at) | not)
          or (trimmed_string($root.release_readiness.override.reason) | not)
        )
      | "- schema v3 release_readiness=go 且存在未覆盖 reachable、skip/excluded/caveat 时，override 必须完整包含 approved_by/approved_at/reason"
    )
  ]
| .[]

#!/usr/bin/env nu

const dependency_section_names = [
  dependencies
  dev-dependencies
  build-dependencies
]

const passthrough_source_keys = [
  path
  git
]

def fail [message: string] {
  error make --unspanned $message
}

def load-toml [path: string] {
  open --raw $path | decode utf-8 | from toml
}

def expect-record [value: any message: string] {
  if (($value | describe) !~ '^record') {
    fail $message
  }

  $value
}

def expect-list [value: any message: string] {
  if (($value | describe) !~ '^list') {
    fail $message
  }

  $value
}

def normalize-catalog-entry [crate_name: string raw_entry: any] {
  let entry_type = ($raw_entry | describe)

  if $entry_type == 'string' {
    return {version: $raw_entry}
  }

  if $entry_type !~ '^record' {
    fail $"catalog entry for '($crate_name)' must be a string or table"
  }

  let normalized = $raw_entry
  let version = ($normalized | get -o version)

  if (($version | describe) != 'string') or ($version | is-empty) {
    fail $"catalog entry for '($crate_name)' must define a non-empty version"
  }

  $normalized
}

def normalize-dependency-spec [crate_name: string raw_spec: any] {
  let spec_type = ($raw_spec | describe)

  if $spec_type == 'bool' {
    if $raw_spec {
      return {}
    }

    fail $"dependency '($crate_name)' cannot be false"
  }

  if $spec_type =~ '^record' {
    return $raw_spec
  }

  fail (
    $"dependency '($crate_name)' must be a table or true in Cargo.poly.toml; "
    + 'string shorthand is not supported because versions come from the shared catalog'
  )
}

def merge-features [catalog_features: any spec_features: any] {
  let catalog_list = if ($catalog_features | describe) == 'nothing' {
    []
  } else {
    expect-list $catalog_features 'catalog dependency features must be a list'
  }

  let spec_list = if ($spec_features | describe) == 'nothing' {
    []
  } else {
    expect-list $spec_features 'dependency features must be a list'
  }

  [$catalog_list $spec_list]
  | flatten
  | reduce --fold [] {|feature, acc|
      if (($feature | describe) != 'string') or ($feature | is-empty) {
        fail 'dependency features must be non-empty strings'
      }

      if $feature in $acc {
        $acc
      } else {
        $acc | append $feature
      }
    }
}

def merge-dependency [crate_name: string raw_spec: any catalog: record] {
  let spec = normalize-dependency-spec $crate_name $raw_spec
  let has_passthrough = ($passthrough_source_keys | any {|key| $spec | columns | any {|column| $column == $key } })

  if ('version' in ($spec | columns)) and (not $has_passthrough) {
    fail (
      $"dependency '($crate_name)' must not declare version in Cargo.poly.toml; "
      + 'move the version into the shared catalog'
    )
  }

  if $has_passthrough {
    return $spec
  }

  if not ($crate_name in ($catalog | columns)) {
    fail $"dependency '($crate_name)' is missing from the shared catalog"
  }

  let merged = ($catalog | get $crate_name | merge $spec)

  if ('features' in (($catalog | get $crate_name) | columns)) or ('features' in ($spec | columns)) {
    $merged | merge {
      features: (merge-features (($catalog | get $crate_name | get -o features)) ($spec | get -o features))
    }
  } else {
    $merged
  }
}

def merge-dependency-table [dependency_table: record catalog: record] {
  $dependency_table
  | columns
  | reduce --fold {} {|crate_name, acc|
      let crate_name = ($crate_name | into string)

      $acc
      | merge {
          $crate_name: (
            merge-dependency $crate_name ($dependency_table | get $crate_name) $catalog
          )
        }
    }
}

def visit [node: any catalog: record] {
  let node_type = ($node | describe)

  if $node_type =~ '^record' {
    $node
    | columns
    | reduce --fold {} {|key, acc|
        let key = ($key | into string)
        let value = ($node | get $key)

        $acc
        | merge {
            $key: (
              if $key in $dependency_section_names {
                merge-dependency-table (
                  expect-record $value $"($key | into string) must be a table"
                ) $catalog
              } else {
                visit $value $catalog
              }
            )
          }
      }
  } else if $node_type =~ '^list' {
    $node | each {|item| visit $item $catalog }
  } else {
    $node
  }
}

def load-catalog [catalog_path: string] {
  let parsed = expect-record (load-toml $catalog_path) 'catalog TOML must be a top-level table'
  let crates = ($parsed | get -o crates)

  if (($crates | describe) !~ '^record') {
    fail 'catalog TOML must define a [crates] table'
  }

  $crates
  | columns
  | reduce --fold {} {|crate_name, acc|
      let crate_name = ($crate_name | into string)

      $acc
      | merge {
          $crate_name: (
            normalize-catalog-entry $crate_name ($crates | get $crate_name)
          )
        }
    }
}

def main [catalog_path: string spec_path: string] {
  let catalog = load-catalog $catalog_path
  let spec = expect-record (load-toml $spec_path) 'Cargo.poly.toml must be a top-level table'

  visit $spec $catalog | to json --indent 2
}

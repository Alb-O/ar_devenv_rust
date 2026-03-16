#!/usr/bin/env nu

def main [spec_path: string scratch_root: string] {
  let spec_path = ($spec_path | path expand)
  let scratch_root = ($scratch_root | path expand)
  let repo_root = ($spec_path | path dirname)

  cp $spec_path ($scratch_root | path join 'Cargo.toml')

  let spec = open $spec_path
  let workspace_cfg = ($spec | get -o workspace)

  if (($workspace_cfg | describe) !~ '^record') {
    return
  }

  let excludes = (
    $workspace_cfg
    | get -o exclude
    | default []
    | each {|pattern|
        if ($pattern | describe) != 'string' {
          []
        } else {
          glob ($repo_root | path join $pattern)
          | each {|match| $match | path expand }
        }
      }
    | flatten
  )

  let members = ($workspace_cfg | get -o members | default [])

  for pattern in $members {
    if ($pattern | describe) != 'string' {
      continue
    }

    for member_dir in (glob ($repo_root | path join $pattern)) {
      let member_dir = ($member_dir | path expand)

      if (($member_dir | path type) != dir) {
        continue
      }

      if $member_dir in $excludes {
        continue
      }

      let source_manifest = ($member_dir | path join 'Cargo.toml')

      if not ($source_manifest | path exists) {
        continue
      }

      let relative_dir = ($member_dir | path relative-to $repo_root)
      let target_dir = ($scratch_root | path join $relative_dir)

      mkdir $target_dir
      cp $source_manifest ($target_dir | path join 'Cargo.toml')
    }
  }
}

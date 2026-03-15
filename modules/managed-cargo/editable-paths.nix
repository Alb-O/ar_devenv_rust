{
  config,
  inputs ? { },
  lib,
}:

let
  isRelativeLockPath = path: path == "." || lib.hasPrefix "./" path || lib.hasPrefix "../" path;

  normalizeLockPath =
    path:
    if path == null then
      null
    else if path == "." then
      toString config.devenv.root
    else if isRelativeLockPath path then
      "${config.devenv.root}/${path}"
    else
      path;

  # Path-backed devenv inputs are evaluated from /nix/store, but the lock file
  # still records the original checkout path that a developer should edit.
  devenvLockPath = "${config.devenv.root}/devenv.lock";
  devenvLock =
    if builtins.pathExists devenvLockPath then
      builtins.fromJSON (builtins.readFile devenvLockPath)
    else
      null;

  editableInputRoot =
    inputName:
    if
      devenvLock == null
      || !(builtins.hasAttr "nodes" devenvLock)
      || !(builtins.hasAttr inputName devenvLock.nodes)
    then
      null
    else
      let
        node = builtins.getAttr inputName devenvLock.nodes;
        original = node.original or { };
        locked = node.locked or { };
      in
      if (locked.type or null) != "path" then
        null
      else
        normalizeLockPath (original.path or locked.path or null);
in
{
  # Only remap path-backed devenv inputs. Other input types do not have a
  # stable local checkout path to point developers at.
  editablePathFor =
    path:
    let
      pathString = toString path;
      matchingInput = builtins.foldl' (
        best: inputName:
        let
          input = builtins.getAttr inputName inputs;
          inputOutPath = if input ? outPath then toString input.outPath else null;
          editRoot = editableInputRoot inputName;
          # Use the most specific matching input so nested input paths still
          # map back to the right checkout root.
          matches =
            inputOutPath != null
            && editRoot != null
            && (pathString == inputOutPath || lib.hasPrefix "${inputOutPath}/" pathString);
          bestLength = if best == null then -1 else builtins.stringLength best.inputOutPath;
          inputLength = if inputOutPath == null then -1 else builtins.stringLength inputOutPath;
        in
        if matches && inputLength > bestLength then
          {
            inherit editRoot inputOutPath;
          }
        else
          best
      ) null (builtins.attrNames inputs);
      suffix =
        if matchingInput == null then
          ""
        else
          builtins.substring (builtins.stringLength matchingInput.inputOutPath) (
            builtins.stringLength pathString - builtins.stringLength matchingInput.inputOutPath
          ) pathString;
    in
    if matchingInput == null then pathString else matchingInput.editRoot + suffix;
}

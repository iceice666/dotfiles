{
  lib,
  stdenv,
  nodejs,
  srcOnly,
  python3,
  cctools,
}:

assert stdenv.buildPlatform.canExecute stdenv.hostPlatform;

stdenv.mkDerivation {
  pname = "nodejs-native-addon-test";
  inherit (nodejs) version;
  dontUnpack = true;
  nativeBuildInputs = [
    nodejs
    python3
  ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [ cctools ];
  env = {
    npm_config_nodedir = "${srcOnly nodejs}";
    npm_config_python = "${python3.interpreter}";
    NIX_NODEJS_BUILDNPMPACKAGE = "1";
  };
  buildPhase = ''
    runHook preBuild
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME"
    printf '%s\n' '{"name":"native-addon-test","version":"1.0.0","private":true,"scripts":{"build":"node-gyp rebuild"}}' > package.json
    printf '%s\n' '{"targets":[{"target_name":"answer","sources":["answer.c"]}]}' > binding.gyp
    cat > answer.c <<'EOF'
    #include <node_api.h>

    static napi_value answer(napi_env env, napi_callback_info info) {
      napi_value value;
      napi_create_int32(env, 42, &value);
      return value;
    }

    static napi_value init(napi_env env, napi_value exports) {
      napi_value function;
      napi_create_function(env, "answer", NAPI_AUTO_LENGTH, answer, NULL, &function);
      napi_set_named_property(env, exports, "answer", function);
      return exports;
    }

    NAPI_MODULE(NODE_GYP_MODULE_NAME, init)
    EOF
    npm --offline run build
    node -e 'require("node:assert/strict").equal(require("./build/Release/answer.node").answer(), 42)'
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp build/Release/answer.node "$out/"
    runHook postInstall
  '';
  meta.platforms = lib.platforms.linux ++ lib.platforms.darwin;
}

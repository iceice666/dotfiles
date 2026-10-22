// Public, unauthenticated TLS regression probes. Also usable as a Node --import
// preload to exercise a packaged application's exact runtime and CA environment.
const hosts = ["example.com"];
for (const suffix of ["", "-aaa"]) {
  for (const kind of ["dv", "ov", "ev"]) {
    for (const generation of ["g3b", "g3c"]) {
      hosts.push(`${kind}-${generation}${suffix}-emudhra.we-have-a-problem.com`);
    }
  }
}

let failures = 0;
for (const [index, host] of hosts.entries()) {
  try {
    const response = await fetch(`https://${host}/`, {
      signal: AbortSignal.timeout(15000),
      redirect: "error",
    });
    await response.body?.cancel();
    if (index === 0 && response.ok) {
      console.log(`PASS positive control: ${host} (${response.status})`);
    } else {
      failures++;
      console.error(`FAIL ${host}: accepted TLS (${response.status})`);
    }
  } catch (error) {
    const code = error.cause?.code ?? error.code ?? "";
    if (index > 0 && /CERT_|SELF_SIGNED|UNABLE_TO_(GET|VERIFY)|INVALID_PURPOSE/.test(code)) {
      console.log(`PASS rejected ${host}: ${code}`);
    } else {
      failures++;
      console.error(`FAIL ${host}: inconclusive transport error ${code}: ${error.message}`);
    }
  }
}
process.exit(failures ? 1 : 0);

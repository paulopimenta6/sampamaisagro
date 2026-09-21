"""Reject observed non-loopback IP calls; ignore Unix IPC and OS netlink queries."""
import ipaddress
import re
import sys
from pathlib import Path


def unexpected(line):
    if "AF_INET" not in line:
        return False
    addresses = re.findall(r'inet_addr\("([^"]+)"\)|inet_pton\(AF_INET6, "([^"]+)"', line)
    if not addresses:
        return True  # Unknown IP sockaddr encoding must not be silently accepted.
    for pair in addresses:
        address = ipaddress.ip_address(next(x for x in pair if x))
        mapped = getattr(address, "ipv4_mapped", None)
        if not (mapped or address).is_loopback:
            return True
    return False


if __name__ == "__main__":
    if sys.argv[1:] == ["--self-test"]:
        assert unexpected('connect(3, {sa_family=AF_INET, sin_addr=inet_addr("203.0.113.1")}, 16)')
        assert unexpected('sendto(3, "dns", 3, 0, {sa_family=AF_INET, sin_addr=inet_addr("8.8.8.8")}, 16)')
        assert not unexpected('connect(3, {sa_family=AF_INET, sin_addr=inet_addr("127.0.0.1")}, 16)')
        assert not unexpected('connect(3, {sa_family=AF_INET6, inet_pton(AF_INET6, "::1", &sin6_addr)}, 28)')
        assert not unexpected('connect(3, {sa_family=AF_UNIX, sun_path="/tmp/socket"}, 16)')
        print("Network trace parser negative/positive controls passed.")
    else:
        trace = Path(sys.argv[1])
        bad = [line for line in trace.read_text(errors="replace").splitlines() if unexpected(line)]
        if bad:
            print("Unexpected external IP operations:\n" + "\n".join(bad[:30]), file=sys.stderr)
            raise SystemExit(1)
        print("No non-loopback IP operations observed in this trace (including child processes).")

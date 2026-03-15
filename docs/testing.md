# Testing

Run full suite:
```bash
forge test -vvv
```

Current suite includes:
- hook integration tests (swap capture, flag mismatch, acquisition path)
- vault unit and fuzz tests
- inherited template tests for baseline hook utilities

Coverage command:
```bash
forge coverage --report lcov
```

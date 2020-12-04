# Spamassassin Lambda Container
* __Runtime__: Python 3.9

Runs [spamassassin](https://spamassassin.apache.org/) on a single email body. The parsed headers are returned.

## Usage
Input event:
```json
{
  "body": "<raw email body>"
}
```
Response:
```json
{
  "isSpam": boolean,
  "score": float,
  "threshold": float,
  "tests": [
    'test1',
    'test2',
    ...
  ]
}
```

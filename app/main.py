import sys
import os
import email
import re
import json
def handler(event, context):
    isSpam = False
    score = 0
    threshold = 0
    tests = []
    try:
        f = open("/tmp/msg", "w")
        f.write(event['body'])
        f.close()

        stream = os.system('/usr/bin/spamassassin -x < /tmp/msg > /tmp/out')
        f = open('/tmp/out', 'r')
        data = email.message_from_file(f)
        f.close()

        status = data.get('X-Spam-Status','')
        print('X-Spam-Status:' + status)
        status = status.replace('\n', '').replace('\r', '').replace('\t', '').replace('autolearn', ' autolearn')
        print('Cleaned X-Spam-Status:' + status)

        if status != '':
            m = re.match("(\w+), score=(\d+\.\d+) required=(\d+\.\d+) tests=([^\s]+)", status)
            if m:
                groups = m.groups()
                print('Matches:' + groups)
                if groups[0] == 'Yes':
                    isSpam = True
                score = float(groups[1])
                threshold = float(groups[2])
                tests = groups[3].split(',')

        result = {
            'isSpam': isSpam,
            'score': score,
            'threshold': threshold,
            'tests': tests
        }
    except:
        print("Error during execution. Returning default")
    finally:
        return result

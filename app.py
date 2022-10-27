from flask import Flask, request, jsonify
import json, requests, re, sqlite3, logging, os, sys, datetime
from os.path import exists
from sendgrid import SendGridAPIClient
from sendgrid.helpers.mail import Mail, From, To

# TODO
# Import CSV
# Random planets
# Generate inventory
# Generate stats

logging.root.setLevel(logging.INFO)
logging.basicConfig(filename="hook.log", level=os.environ.get("LOGLEVEL", "INFO"))

db_path = 'db.sq3'
db = sqlite3.connect(db_path, isolation_level=None)
db.execute('pragma journal_mode=wal;')

api_key = os.getenv('API_KEY')
sg_api = os.getenv('SG_API')
template_id = os.getenv('TEMPLATE_ID')
url = os.getenv('URL')

headers = {"Content-Type": "application/json",
        "Authorization": f"Basic {api_key}"}

exist = exists('planets.csv')
if exist == True:
    logging.info('import_csv()')

def dict_factory(cursor, row):
    d = {}
    for idx, col in enumerate(cursor.description):
        d[col[0]] = row[idx]
    return d

def get_val(lookup,key,value):
    query = f'SELECT "{lookup}" FROM planets WHERE "{key}" is "{value}" LIMIT 1;'
    conn = sqlite3.connect(db_path, isolation_level=None)
    conn.row_factory = dict_factory
    cur = conn.cursor()
    answer_raw = cur.execute(query).fetchall()
    if not answer_raw:
        return None
    else:
        answer_json = json.loads(json.dumps(answer_raw))
        result = answer_json[0][lookup]
        return result

def upd_val(key,value,lookup,identifier):
    timestamp = datetime.now()
    conn = sqlite3.connect(db_path, isolation_level=None)
    query = f'UPDATE "planets" SET \
        "{key}" = "{value}" \
        WHERE {lookup} is "{identifier}";'
    cur = conn.cursor()
    cur.execute(query)
    conn.commit()
    logging.info(f"• {identifier} UPDATE {key} '{value}' @ {timestamp}")


def is_sold(planet):
    query = f'SELECT Email FROM planets WHERE Planet is "{planet}";'
    conn = sqlite3.connect(db_path, isolation_level=None)
    conn.row_factory = dict_factory
    cur = conn.cursor()
    answer_raw = cur.execute(query).fetchall()
    if not answer_raw:
        return None
    else:
        answer_json = json.loads(json.dumps(answer_raw))
        result = answer_json[0]['Email']
    if result == None:
        return False
    else:
        return True

def purchase_planet(planet,email):
    sold = is_sold(planet)
    time = datetime.now()
    if sold == True:
        logging.warning(f'{planet} already sold!')
    elif sold == None:
        logging.warning(f'{planet} not found!')
    else:
        code = get_val('Invite URL','Planet',planet)
        code_text = get_val('Ticket','Planet',planet)
        email_sale(email,planet,code,code_text)
        upd_val('Timestamp',time,'Planet',planet)

def email_sale(email,planet_name,planet_code,code_text):
    message = Mail(
        from_email='matwet@subject.network',
        to_emails=email,
        subject='🚀Your Urbit is ready'
        )
    message.add_bcc('matwet+sold@subject.network')
    message.template_id = template_id
    message.dynamic_template_data = {
        'planet-code': reg_code,
        'planet-name': planet_name,
        'code-text': code_text
    }
    try:
        sg = SendGridAPIClient(sg_api)
        response = sg.send(message)
        logging.info('[Sendgrid] New sale email sent')
        logging.info(response.status_code)
    except Exception as e:
        logging.exception(e)
    return

app = Flask(__name__)

@app.route('/listen', methods=['POST'])
def hook():
    payload = request.get_json()
    status, invoice = None, None
    if 'event' in payload.keys():
        status = payload['event']['name']
    if 'data' in payload.keys():
        invoice = payload['data']['id']
        get_url = f'{url}/invoices/{invoice}'
        response = requests.get(get_url,headers=headers).json()
        email = response['data']['buyer']['email']
        planet = response['data']['itemCode']
    if status == 'invoice_confirmed':
        purchase_planet(planet,email)
    return jsonify(status = 'ok'),200

if __name__ == "__main__":
  app.run(host='0.0.0.0')



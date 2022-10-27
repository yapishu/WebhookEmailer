from flask import Flask, request, jsonify
import json, requests, re, sqlite3, logging, os, sys, datetime, subprocess
from os.path import exists
from sendgrid import SendGridAPIClient
from sendgrid.helpers.mail import Mail, From, To
from boto3 import session
from botocore.client import Config

# TODO
# Import CSV
# Random planets
# Generate inventory
# Generate stats

logging.root.setLevel(logging.INFO)
logging.basicConfig(filename="/data/hook.log", level=os.environ.get("LOGLEVEL", "INFO"))

db_path = '/data/db.sq3'
db = sqlite3.connect(db_path, isolation_level=None)
db.execute('pragma journal_mode=wal;')
db.execute('CREATE TABLE IF NOT EXISTS planets (id INTEGER, \
Number INTEGER NULL, Planet TEXT NULL,"Invite URL" TEXT NULL, \
Point INTEGER NULL, Ticket TEXT NULL, Email TEXT NULL, \
Timestamp TEXT NULL, PRIMARY KEY ("id" AUTOINCREMENT) );')
db.execute('CREATE TABLE IF NOT EXISTS planets_listed (id INTEGER, \
Number INTEGER NULL, Planet TEXT NULL,"Invite URL" TEXT NULL, \
Point INTEGER NULL, Ticket TEXT NULL, Email TEXT NULL, \
Timestamp TEXT NULL, PRIMARY KEY ("id" AUTOINCREMENT) );')
db.execute('CREATE TABLE IF NOT EXISTS planets_sold (id INTEGER, \
Number INTEGER NULL, Planet TEXT NULL,"Invite URL" TEXT NULL, \
Point INTEGER NULL, Ticket TEXT NULL, Email TEXT NULL, \
Timestamp TEXT NULL, PRIMARY KEY ("id" AUTOINCREMENT) );')

# Migrate old sales
query = 'INSERT INTO planets_sold SELECT * FROM planets WHERE Email IS NOT NULL;'
query ='DELETE FROM planets WHERE Email IS NOT NULL;'

api_key = os.getenv('API_KEY')
sg_api = os.getenv('SG_API')
template_id = os.getenv('TEMPLATE_ID')
url = os.getenv('URL')
s3_access = os.getenv('S3_ACCESS')
s3_secret = os.getenv('S3_SECRET')
bucket = os.getenv('S3_BUCKET')

headers = {"Content-Type": "application/json",
        "Authorization": f"Basic {api_key}"}

db_exists = exists(db_path)
csv_exists = exists('planets.csv')
if csv_exists == True:
    logging.info('import_csv()')
if (db_exists == False) and (csv_exists == False):
    logging.error('No DB/No CSV -- exiting')
    sys.exit()

def import_csv():
    conn = sqlite3.connect(db_path, isolation_level=None)
    dedupe = 'DELETE FROM planets WHERE rowid NOT IN (SELECT MIN(rowid) FROM planets GROUP BY Planet);'
    return

def dict_factory(cursor, row):
    d = {}
    for idx, col in enumerate(cursor.description):
        d[col[0]] = row[idx]
    return d

def get_val(db,lookup,key,value):
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

def move_val(source,id,dest):
    conn = sqlite3.connect(db_path, isolation_level=None)
    cur = conn.cursor()
    query = f'INSERT INTO {dest} SELECT * FROM {source} WHERE rowid is "{id}";'
    cur.execute(query)
    query = f'DELETE FROM {source} WHERE rowid is {id};'
    cur.execute(query)
    query = f'VACUUM;'
    cur.execute(query)
    query = f'UPDATE {source} SET Number = rowid;'
    cur.execute(query)
    query = f'UPDATE {dest} SET Number = rowid;'
    cur.execute(query)
    conn.commit()

def get_next_avail():
    conn = sqlite3.connect(db_path, isolation_level=None)
    query = 'SELECT Planet FROM planets WHERE Email is NULL LIMIT 1;'
    conn = sqlite3.connect(db_path, isolation_level=None)
    conn.row_factory = dict_factory
    cur = conn.cursor()
    answer_raw = cur.execute(query).fetchall()
    if not answer_raw:
        return None
    else:
        answer_json = json.loads(json.dumps(answer_raw))
        result = answer_json[0]['Planet']
        return result

def get_last_avail():
    conn = sqlite3.connect(db_path, isolation_level=None)
    query = 'SELECT Planet FROM planets WHERE Email is NULL ORDER BY rowid DESC LIMIT 1;'
    cur = conn.cursor()
    cur.execute(query)
    answer_raw = cur.execute(query).fetchall()
    if not answer_raw:
        return None
    else:
        answer_json = json.loads(json.dumps(answer_raw))
        result = answer_json[0]['Planet']
        return result

def db_count(table):
    conn = sqlite3.connect(db_path, isolation_level=None)
    if table == 'planets':
        query = 'SELECT COUNT(*) FROM planets;'
    elif table == 'sold':
        query = 'SELECT COUNT(*) FROM planets_sold;'
    else:
        return False
    cur = conn.cursor()
    answer_raw = cur.execute(query).fetchall()
    answer_json = json.loads(json.dumps(answer_raw))
    result = answer_json[0][0]
    return result

def upd_val(db,key,value,lookup,identifier):
    timestamp = datetime.now()
    conn = sqlite3.connect(db_path, isolation_level=None)
    query = f'UPDATE {db} SET \
        "{key}" = "{value}" \
        WHERE {lookup} is "{identifier}";'
    cur = conn.cursor()
    cur.execute(query)
    conn.commit()
    logging.info(f"• {identifier} UPDATE {key} '{value}' @ {timestamp}")

def is_sold(planet):
    query = f'SELECT Email FROM planets_sold WHERE Planet is "{planet}";'
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
    # If specific planet:
    db = 'planets_listed'
    if planet == 'Planet':
        planet = get_next_avail()
        db = 'planets'
    sold = is_sold(planet)
    time = datetime.now()
    if sold == True:
        logging.warning(f'{planet} already sold!')
    elif sold == None:
        logging.warning(f'{planet} not found!')
    else:
        code = get_val(db,'Invite URL','Planet',planet)
        code_text = get_val(db,'Ticket','Planet',planet)
        email_sale(email,planet,code,code_text)
        upd_val(db,'Timestamp',time,'Planet',planet)
        planet_id = get_val(db,'planets','rowid','Planet',planet)
        move_val('planets','planets_sold',planet_id)
        logging.info(f'{planet} marked as sold')

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

def inventory_gen(num):
    cmd = 'mkdir -p /data/sigil'
    process = subprocess.Popen(cmd.split(), stdout=subprocess.PIPE)
    output, error = process.communicate()
    last_planet = get_last_avail()
    last_uid = int(get_value('planets','rowid','Planet',last_planet))
    first_uid = last_uid - int(num)
    while first_uid <= last_uid:
        planet = get_val('planets','Planet','rowid',first_uid)
        cmd = f'echo "{planet}"|/app/sigils/sigil>/data/sigil/{planet}.svg'
        process = subprocess.Popen(cmd.split(), stdout=subprocess.PIPE)
        output, error = process.communicate()
        s3_upload(f'/data/sigil/{planet}.svg')
        inv = open("/data/sigil/inv.txt", "a")
        inv.write(f'''
        ''')
        inv.close()
        first_uid += 1

def s3_upload(file):
    name = os.path.basename(file)
    session = session.Session()
    client = session.client('s3',
        region_name='nyc3',
        endpoint_url=f'https://{S3_URL}',
        aws_access_key_id=S3_ACCESS,
        aws_secret_access_key=S3_SECRET)
    client.upload_file(file, bucket, f'sigils/{name}')

app = Flask(__name__)

@app.route('/', methods=['GET'])
def stats():
    # avail = get_last_avail()
    # avail = get_val('planets','rowid','Planet',avail)
    # avail = {'available':avail}
    # sold = 
    # recent = {'most_recent':{'planet':planet,'buyer':email}
    # return jsonify(avail,sold,recent)
    return True

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



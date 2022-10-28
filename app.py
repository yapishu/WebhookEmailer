from flask import Flask, request, jsonify
import json, requests, re, sqlite3, logging, os, sys, subprocess, boto3
from pathlib import Path
from datetime import datetime
from os.path import exists
from sendgrid import SendGridAPIClient
from sendgrid.helpers.mail import Mail, From, To
from boto3 import session
from botocore.client import Config

# TODO
# Import CSV
# Generate stats

logging.root.setLevel(logging.INFO)
logging.basicConfig(filename="/data/hook.log", level=os.environ.get("LOGLEVEL", "INFO"))

db_path = '/data/db.sq3'
db = sqlite3.connect(db_path, isolation_level=None)
db.execute('pragma journal_mode=wal;')
db.execute('CREATE TABLE IF NOT EXISTS planets_sold AS \
    SELECT * FROM planets WHERE Email IS NOT NULL;')
db.execute('CREATE TABLE IF NOT EXISTS planets_listed AS \
    SELECT * FROM planets WHERE 0;')

# Migrate old sales
query = 'INSERT INTO planets_sold SELECT * FROM planets WHERE Email IS NOT NULL;'
query ='DELETE FROM planets WHERE Email IS NOT NULL;'

api_key = os.getenv('API_KEY')
sg_api = os.getenv('SG_API')
template_id = os.getenv('TEMPLATE_ID')
url = os.getenv('URL')
s3_access = os.getenv('S3_ACCESS')
s3_secret = os.getenv('S3_SECRET')
s3_url = os.getenv('S3_URL')
bucket = os.getenv('S3_BUCKET')

session = session.Session()
s3client = session.client('s3',
    region_name='nyc3',
    endpoint_url=f'https://{s3_url}',
    aws_access_key_id=s3_access,
    aws_secret_access_key=s3_secret)
s3 = boto3.resource('s3')

headers = {"Content-Type": "application/json",
        "Authorization": f"Basic {api_key}"}

db_exists = exists(db_path)
csv_exists = exists('planets.csv')
if csv_exists == True:
    logging.info('import_csv()')
if (db_exists == False) and (csv_exists == False):
    logging.error('• No DB/No CSV -- exiting')
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

def move_val(source,lookup,identifier,dest):
    planet = get_val(source,'Planet',lookup,identifier)
    logging.info(f'• Moving {planet} (id:{identifier}) from {source} to {dest}')
    conn = sqlite3.connect(db_path, isolation_level=None)
    cur = conn.cursor()
    query = f'INSERT INTO {dest} SELECT * FROM {source} WHERE {lookup} is {identifier};'
    cur.execute(query)
    query = f'DELETE FROM {source} WHERE {lookup} is {identifier};'
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
        result = answer_json[0][0]
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
    if planet == 'planet':
        planet = get_next_avail()
        db = 'planets'
    exists = get_val('planets','rowid','Planet',planet)
    if exists == None:
        logging.warning(f'• {planet} Not listed; may be dupe webhook call')
        return False
    time = datetime.now()
    code = get_val(db,'Invite URL','Planet',planet)
    code_text = get_val(db,'Ticket','Planet',planet)
    email_sale(email,planet,code,code_text)
    upd_val(db,'Timestamp',time,'Planet',planet)
    upd_val(db,'Email',email,'Planet',planet)
    planet_id = get_val('planets','rowid','Planet',planet)
    move_val('planets','rowid',planet_id,'planets_sold')
    logging.info(f'• {planet} marked as sold')

def email_sale(email,planet_name,planet_code,code_text):
    if email == None:
        logging.warning(f'{planet_name}: No email extracted!')
        return False
    message = Mail(
        from_email='matwet@subject.network',
        to_emails=email,
        subject='🚀Your Urbit is ready'
        )
    message.add_bcc('matwet+sold@subject.network')
    message.template_id = template_id
    message.dynamic_template_data = {
        'planet-code': planet_code,
        'planet-name': planet_name,
        'code-text': code_text
    }
    try:
        sg = SendGridAPIClient(sg_api)
        response = sg.send(message)
        logging.info('• Sale email sent')
        logging.info(response.status_code)
    except Exception as e:
        logging.exception(f'• {e}')
    return

def inventory_gen(num):
    Path("/data/inventory/img").mkdir(parents=True, exist_ok=True)
    inv = open("/data/inventory/inv.txt", "w+")
    inv.write(f'''Planet:
  title: planet
  price: 10
  image: https://urbits3.ams3.digitaloceanspaces.com/anim2.gif
  price_type: fixed
  disabled: false
  inventory: 128
  buyButtonText: ₿uy

''')
    inv.close()
    last_planet = get_last_avail()
    last_uid = int(get_val('planets','Number','Planet',last_planet))
    first_uid = last_uid - int(num)
    logging.info(f'• Generating inventory for rows {first_uid}-{last_uid}')
    begin, end = first_uid, last_uid
    while begin < end:
        planet = get_val('planets','Planet','Number',end)
        sig_path = f'/data/inventory/img/{planet}.svg'
        cmd = f'echo "{planet}"|/app/sigil/sigil'
        process = subprocess.Popen(cmd,shell=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
        process.wait()
        output, error = process.communicate()
        output = output.decode("utf-8")
        output = output.replace("'black'", '"#333"')
        sig = open(sig_path, "w+")
        sig.write(output)
        sig.close()
        s3_upload(sig_path)
        inv = open("/data/inventory/inv.txt", "a")
        inv.write(f'''{planet}:
  title: {planet}
  price: 15
  image: https://{s3_url}/urbits3/sigils/{planet}.svg
  price_type: fixed
  disabled: false
  inventory: 1
  buyButtonText: ₿uy

''')
        inv.close()
        move_val('planets','Number',end,'planets_listed')
        end -= 1

def s3_upload(filepath):
    name = os.path.basename(filepath)
    s3client.upload_file(filepath, bucket, f'sigils/{name}',ExtraArgs={'ContentType': 'image/svg+xml'})
    s3client.put_object_acl( ACL='public-read', Bucket=bucket, Key=f'sigils/{name}' )


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
        logging.info(f'• Selling {planet} to {email}')
        purchase_planet(planet,email)
    return jsonify(status = 'ok'),200

if __name__ == "__main__":
  app.run(host='0.0.0.0')



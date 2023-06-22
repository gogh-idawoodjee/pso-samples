import json
import pandas as pd

# JSON data
data = '''
{
    "dsScheduleData": {
        "@xmlns": "http://360Scheduling.com/Schema/dsScheduleData.xsd",
        "Appointment_Offer": [
            {
                "appointment_request_id": "2023-06-20T14:15:54",
                "id": "0",
                "offer_start_datetime": "2023-06-21T08:00:00+00:00",
                "offer_end_datetime": "2023-06-21T10:00:00+00:00",
                "offer_value": "975.7602016828832",
                "plan_id": "133932",
                "available": "true",
                "reason_type_id": "0",
                "window_start_datetime": "2023-06-21T08:00:00+00:00",
                "window_end_datetime": "2023-06-21T10:00:00+00:00",
                "prospective_resource_id": "Arshpreet Singh",
                "prospective_allocation_start": "2023-06-21T09:00:00+00:00"
            },
            {
                "appointment_request_id": "2023-06-20T14:15:54",
                "id": "1",
                "offer_start_datetime": "2023-06-21T08:30:00+00:00",
                "offer_end_datetime": "2023-06-21T10:30:00+00:00",
                "offer_value": "975.7602016828832",
                "plan_id": "133932",
                "available": "true",
                "reason_type_id": "0",
                "window_start_datetime": "2023-06-21T08:30:00+00:00",
                "window_end_datetime": "2023-06-21T10:30:00+00:00",
                "prospective_resource_id": "Arshpreet Singh",
                "prospective_allocation_start": "2023-06-21T10:00:00+00:00"
            },
            {
                "appointment_request_id": "2023-06-20T14:15:54",
                "id": "2",
                "offer_start_datetime": "2023-06-21T09:00:00+00:00",
                "offer_end_datetime": "2023-06-21T11:00:00+00:00",
                "offer_value": "890.9423791592596",
                "plan_id": "133932",
                "available": "true",
                "reason_type_id": "0",
                "window_start_datetime": "2023-06-21T09:00:00+00:00",
                "window_end_datetime": "2023-06-21T11:00:00+00:00",
                "prospective_resource_id": "Tyler Pilipow",
                "prospective_allocation_start": "2023-06-21T09:00:00+00:00"
            },
            {
                "appointment_request_id": "2023-06-20T14:15:54",
                "id": "3",
                "offer_start_datetime": "2023-06-21T09:30:00+00:00",
                "offer_end_datetime": "2023-06-21T11:30:00+00:00",
                "offer_value": "735.4615698499574",
                "plan_id": "133932",
                "available": "true",
                "reason_type_id": "0",
                "window_start_datetime": "2023-06-21T09:30:00+00:00",
                "window_end_datetime": "2023-06-21T11:30:00+00:00",
                "prospective_resource_id": "Nicolaas Vandenameele",
                "prospective_allocation_start": "2023-06-21T10:43:55+00:00"
            },
            {
                "appointment_request_id": "2023-06-20T14:15:54",
                "id": "4",
                "offer_start_datetime": "2023-06-21T10:00:00+00:00",
                "offer_end_datetime": "2023-06-21T12:00:00+00:00",
                "offer_value": "974.7746016484093",
                "plan_id": "133932",
                "available": "true",
                "reason_type_id": "0",
                "window_start_datetime": "2023-06-21T10:00:00+00:00",
                "window_end_datetime": "2023-06-21T12:00:00+00:00",
                "prospective_resource_id": "Arshpreet Singh",
                "prospective_allocation_start": "2023-06-21T12:00:00+00:00"
            },
            {
                "appointment_request_id": "2023-06-20T14:15:54",
                "id": "5",
                "offer_start_datetime": "2023-06-21T10:30:00+00:00",
                "offer_end_datetime": "2023-06-21T12:30:00+00:00",
                "offer_value": "803.089967129285",
                "plan_id": "133932",
                "available": "true",
                "reason_type_id": "0",
                "window_start_datetime": "2023-06-21T10:30:00+00:00",
                "window_end_datetime": "2023-06-21T12:30:00+00:00",
                "prospective_resource_id": "Sean Hootz",
                "prospective_allocation_start": "2023-06-21T11:25:59+00:00"
            },
            {
                "appointment_request_id": "2023-06-20T14:15:54",
                "id": "6",
                "offer_start_datetime": "2023-06-22T08:00:00+00:00",
                "offer_end_datetime": "2023-06-22T10:00:00+00:00",
                "offer_value": "952.1303530749315",
                "plan_id": "133932",
                "available": "true",
                "reason_type_id": "0",
                "window_start_datetime": "2023-06-22T08:00:00+00:00",
                "window_end_datetime": "2023-06-22T10:00:00+00:00",
                "prospective_resource_id": "Arshpreet Singh",
                "prospective_allocation_start": "2023-06-22T08:00:00+00:00"
            },
            {
                "appointment_request_id": "2023-06-20T14:15:54",
                "id": "7",
                "offer_start_datetime": "2023-06-22T08:30:00+00:00",
                "offer_end_datetime": "2023-06-22T10:30:00+00:00",
                "offer_value": "951.5898589583021",
                "plan_id": "133932",
                "available": "true",
                "reason_type_id": "0",
                "window_start_datetime": "2023-06-22T08:30:00+00:00",
                "window_end_datetime": "2023-06-22T10:30:00+00:00",
                "prospective_resource_id": "Arshpreet Singh",
                "prospective_allocation_start": "2023-06-22T09:00:00+00:00"
            },
            {
                "appointment_request_id": "2023-06-20T14:15:54",
                "id": "8",
                "offer_start_datetime": "2023-06-22T09:00:00+00:00",
                "offer_end_datetime": "2023-06-22T11:00:00+00:00",
                "offer_value": "951.0479590925229",
                "plan_id": "133932",
                "available": "true",
                "reason_type_id": "0",
                "window_start_datetime": "2023-06-22T09:00:00+00:00",
                "window_end_datetime": "2023-06-22T11:00:00+00:00",
                "prospective_resource_id": "Arshpreet Singh",
                "prospective_allocation_start": "2023-06-22T10:00:00+00:00"
            },
            {
                "appointment_request_id": "2023-06-20T14:15:54",
                "id": "9",
                "offer_start_datetime": "2023-06-22T09:30:00+00:00",
                "offer_end_datetime": "2023-06-22T11:30:00+00:00",
                "offer_value": "904.0033534732695",
                "plan_id": "133932",
                "available": "true",
                "reason_type_id": "0",
                "window_start_datetime": "2023-06-22T09:30:00+00:00",
                "window_end_datetime": "2023-06-22T11:30:00+00:00",
                "prospective_resource_id": "Dan Streisel",
                "prospective_allocation_start": "2023-06-22T09:30:00+00:00"
            },
            {
                "appointment_request_id": "2023-06-20T14:15:54",
                "id": "10",
                "offer_start_datetime": "2023-06-22T10:00:00+00:00",
                "offer_end_datetime": "2023-06-22T12:00:00+00:00",
                "offer_value": "949.9598525544247",
                "plan_id": "133932",
                "available": "true",
                "reason_type_id": "0",
                "window_start_datetime": "2023-06-22T10:00:00+00:00",
                "window_end_datetime": "2023-06-22T12:00:00+00:00",
                "prospective_resource_id": "Arshpreet Singh",
                "prospective_allocation_start": "2023-06-22T12:00:00+00:00"
            },
            {
                "appointment_request_id": "2023-06-20T14:15:54",
                "id": "11",
                "offer_start_datetime": "2023-06-22T10:30:00+00:00",
                "offer_end_datetime": "2023-06-22T12:30:00+00:00",
                "offer_value": "902.9123216642477",
                "plan_id": "133932",
                "available": "true",
                "reason_type_id": "0",
                "window_start_datetime": "2023-06-22T10:30:00+00:00",
                "window_end_datetime": "2023-06-22T12:30:00+00:00",
                "prospective_resource_id": "Dan Streisel",
                "prospective_allocation_start": "2023-06-22T10:30:00+00:00"
            },
            {
                "appointment_request_id": "2023-06-20T14:15:54",
                "id": "12",
                "offer_start_datetime": "2023-06-23T08:00:00+00:00",
                "offer_end_datetime": "2023-06-23T10:00:00+00:00",
                "offer_value": "902.9673930607478",
                "plan_id": "133932",
                "available": "true",
                "reason_type_id": "0",
                "window_start_datetime": "2023-06-23T08:00:00+00:00",
                "window_end_datetime": "2023-06-23T10:00:00+00:00",
                "prospective_resource_id": "Arshpreet Singh",
                "prospective_allocation_start": "2023-06-23T08:00:00+00:00"
            },
            {
                "appointment_request_id": "2023-06-20T14:15:54",
                "id": "13",
                "offer_start_datetime": "2023-06-23T08:30:00+00:00",
                "offer_end_datetime": "2023-06-23T10:30:00+00:00",
                "offer_value": "891.6338804804659",
                "plan_id": "133932",
                "available": "true",
                "reason_type_id": "0",
                "window_start_datetime": "2023-06-23T08:30:00+00:00",
                "window_end_datetime": "2023-06-23T10:30:00+00:00",
                "prospective_resource_id": "Arshpreet Singh",
                "prospective_allocation_start": "2023-06-23T09:00:00+00:00"
            },
            {
                "appointment_request_id": "2023-06-20T14:15:54",
                "id": "14",
                "offer_start_datetime": "2023-06-23T09:00:00+00:00",
                "offer_end_datetime": "2023-06-23T11:00:00+00:00",
                "offer_value": "880.1714369482715",
                "plan_id": "133932",
                "available": "true",
                "reason_type_id": "0",
                "window_start_datetime": "2023-06-23T09:00:00+00:00",
                "window_end_datetime": "2023-06-23T11:00:00+00:00",
                "prospective_resource_id": "Arshpreet Singh",
                "prospective_allocation_start": "2023-06-23T10:00:00+00:00"
            },
            {
                "appointment_request_id": "2023-06-20T14:15:54",
                "id": "15",
                "offer_start_datetime": "2023-06-23T09:30:00+00:00",
                "offer_end_datetime": "2023-06-23T11:30:00+00:00",
                "offer_value": "825.8175284563076",
                "plan_id": "133932",
                "available": "true",
                "reason_type_id": "0",
                "window_start_datetime": "2023-06-23T09:30:00+00:00",
                "window_end_datetime": "2023-06-23T11:30:00+00:00",
                "prospective_resource_id": "Tyler Pilipow",
                "prospective_allocation_start": "2023-06-23T11:00:00+00:00"
            },
            {
                "appointment_request_id": "2023-06-20T14:15:54",
                "id": "16",
                "offer_start_datetime": "2023-06-23T10:00:00+00:00",
                "offer_end_datetime": "2023-06-23T12:00:00+00:00",
                "offer_value": "814.1501714091219",
                "plan_id": "133932",
                "available": "true",
                "reason_type_id": "0",
                "window_start_datetime": "2023-06-23T10:00:00+00:00",
                "window_end_datetime": "2023-06-23T12:00:00+00:00",
                "prospective_resource_id": "Tyler Pilipow",
                "prospective_allocation_start": "2023-06-23T10:00:00+00:00"
            },
            {
                "appointment_request_id": "2023-06-20T14:15:54",
                "id": "17",
                "offer_start_datetime": "2023-06-23T10:30:00+00:00",
                "offer_end_datetime": "2023-06-23T12:30:00+00:00",
                "offer_value": "874.1780712932589",
                "plan_id": "133932",
                "available": "true",
                "reason_type_id": "0",
                "window_start_datetime": "2023-06-23T10:30:00+00:00",
                "window_end_datetime": "2023-06-23T12:30:00+00:00",
                "prospective_resource_id": "Dan Streisel",
                "prospective_allocation_start": "2023-06-23T10:30:00+00:00"
            },
            {
                "appointment_request_id": "2023-06-20T14:15:54",
                "id": "18",
                "offer_start_datetime": "2023-06-26T08:00:00+00:00",
                "offer_end_datetime": "2023-06-26T10:00:00+00:00",
                "offer_value": "0",
                "plan_id": "133932",
                "available": "false",
                "reason_type_id": "320",
                "window_start_datetime": "2023-06-26T08:00:00+00:00",
                "window_end_datetime": "2023-06-26T10:00:00+00:00"
            },
            {
                "appointment_request_id": "2023-06-20T14:15:54",
                "id": "19",
                "offer_start_datetime": "2023-06-26T08:30:00+00:00",
                "offer_end_datetime": "2023-06-26T10:30:00+00:00",
                "offer_value": "0",
                "plan_id": "133932",
                "available": "false",
                "reason_type_id": "320",
                "window_start_datetime": "2023-06-26T08:30:00+00:00",
                "window_end_datetime": "2023-06-26T10:30:00+00:00"
            },
            {
                "appointment_request_id": "2023-06-20T14:15:54",
                "id": "20",
                "offer_start_datetime": "2023-06-26T09:00:00+00:00",
                "offer_end_datetime": "2023-06-26T11:00:00+00:00",
                "offer_value": "0",
                "plan_id": "133932",
                "available": "false",
                "reason_type_id": "320",
                "window_start_datetime": "2023-06-26T09:00:00+00:00",
                "window_end_datetime": "2023-06-26T11:00:00+00:00"
            }
        ],
        "Plan": {
            "id": "133932",
            "time_taken": "PT0S",
            "plan_type": "CHANGE",
            "output_datetime": "2023-06-20T14:15:40.617+00:00",
            "input_reference_internal_id": "11800",
            "travel_type": "Lat/Long",
            "schedule_from": "2023-06-20T14:15:54+00:00",
            "schedule_to": "2023-08-25T00:00:00+00:00",
            "input_reference_date_time": "2023-06-20T14:15:54+00:00",
            "input_reference_id": "CHANGE_2023-06-20T14:15:54",
            "organisation_id": "1",
            "dataset_id": "ST_TEST",
            "broadcast_id": "d1a9dd2247dd422c8e5d70165ae5fbc3",
            "software_version": "6.11.0.5",
            "allocation_type": "2",
            "profile_id": "DEFAULT",
            "load_status": "0",
            "appointment_window_end": "2023-08-25T00:00:00+00:00",
            "application_type_id": "ABE",
            "application_instance_id": "ISH-PSO-01"
        }
    }
}
'''

# Parse JSON data
json_data = json.loads(data)

# Extract relevant data
appointment_offers = json_data['dsScheduleData']['Appointment_Offer']
table_data = []

for offer in appointment_offers:
    # Only get the available offers
    if offer['available'].lower() == 'true':
        table_data.append({
            'id': offer['id'],
            'offer_value': offer['offer_value'],
            'window_start': offer['window_start_datetime'],
            'window_end': offer['window_end_datetime'],
            'resource':offer['prospective_resource_id']
        })

# Create a DataFrame from the table data
df = pd.DataFrame(table_data)

# Display the DataFrame
print(df)
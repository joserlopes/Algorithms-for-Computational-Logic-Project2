#!/usr/bin/python3
# alc24 - 19 - project2
# DO NOT remove or edit the lines above. Thank you.

import sys
from z3 import (
    Bool,
    sat,
    Or,
    Optimize,
    Not,
    Implies,
    Sum,
    If,
)

from datetime import datetime

base_city = None
n_cities = 0
n_flights = 0
n_nights = 0
cities = []
flights = []

date_format = "%d/%m"


def parse():
    global base_city
    global n_cities
    global n_flights
    global n_nights
    lines = []

    for line in sys.stdin:
        if line != "\n":
            lines.append(line.strip())

    n_cities = int(lines[0])
    base_city = tuple(lines[1].split()) + (1,)
    cities.append(
        {
            "name": base_city[0],
            "airport": base_city[1],
            "min_nights": 0,
            "max_nights": 0,
            "id": base_city[2],
        }
    )
    for city, id in zip(lines[2 : 2 + n_cities - 1], range(2, n_cities + 2)):
        info = city.split()
        cities.append(
            {
                "name": info[0],
                "airport": info[1],
                "min_nights": int(info[2]),
                "max_nights": int(info[3]),
                "id": id,
            }
        )
        n_nights += int(info[2])
    n_flights = int(lines[2 + n_cities - 1])
    for flight, id in zip(
        lines[2 + n_cities : 2 + n_cities + n_flights], range(1, n_flights + 1)
    ):
        info = flight.split()
        flights.append(
            {
                "date": info[0],
                "og_airport": info[1],
                "dest_airport": info[2],
                "dep_time": info[3],
                "arr_time": info[4],
                "price": int(info[5]),
                "id": id,
            }
        )


def airport_to_clause(airport):
    for city in cities:
        if city["airport"] == airport:
            return city["id"] - 1


def airport_to_city(airport):
    for city in cities:
        if city["airport"] == airport:
            return city


# dateA is "after" _nights_ nights comparing to dateB
def after_k_nights(dateA, nights, dateB):
    dateA = datetime.strptime(dateA, date_format)
    dateB = datetime.strptime(dateB, date_format)

    return (dateA - dateB).days == nights


# dateA is more than "after" _nights_ nights comparing to dateB
def greater_than_k_nights(dateA, nights, dateB):
    dateA = datetime.strptime(dateA, date_format)
    dateB = datetime.strptime(dateB, date_format)

    return (dateA - dateB).days > nights


# dateA is "between" _max_nights_ and _min_nights_ nights comparing to dateB
def between_k_nights(dateA, min_nights, max_nights, dateB):
    dateA = datetime.strptime(dateA, date_format)
    dateB = datetime.strptime(dateB, date_format)

    return min_nights <= (dateA - dateB).days <= max_nights


def date_difference(dateA, dateB):
    dateA = datetime.strptime(dateA, date_format)
    dateB = datetime.strptime(dateB, date_format)

    return dateA - dateB


parse()

variables = []

# The traveler has left city i
for i in range(n_cities):
    variables += [Bool(f"c_{i}")]

# The traveler has arrived at city i
for i in range(n_cities):
    variables += [Bool(f"c'_{i}")]

# The traveler has taken the flight i
for i in range(n_flights):
    variables += [Bool(f"f_{i}")]


solver = Optimize()

for i in range(n_cities * 2):
    # I must have left every city and arrived at every city
    solver.add(variables[i])

# If I haven't left base city, I can't have left any other city
for i in range(1, n_cities):
    solver.add(Implies(Not(variables[0]), Not(variables[i])))

# If I have arrived at city base, I have to have arrived at every other city
for i in range(n_cities + 1, n_cities * 2):
    solver.add(Implies(variables[n_cities], variables[i]))

same_og = {}
same_dest = {}
same_date = {}
for i in range(n_flights):
    flightA = flights[i]
    idA = flightA["id"] + n_cities * 2 - 1
    og_airport = flightA["og_airport"]
    dest_airport = flightA["dest_airport"]
    dateA = flightA["date"]
    og_city_clause = airport_to_clause(og_airport)
    dest_city_clause = airport_to_clause(dest_airport) + n_cities

    # If I have left city i then ci must be true
    solver.add(Implies(variables[idA], variables[og_city_clause]))
    # If I have arrived at city j then c'i must be true
    solver.add(Implies(variables[idA], variables[dest_city_clause]))

    if og_airport not in same_og:
        same_og[og_airport] = [variables[idA]]
    else:
        same_og[og_airport].append(variables[idA])

    if dest_airport not in same_dest:
        same_dest[dest_airport] = [variables[idA]]
    else:
        same_dest[dest_airport].append(variables[idA])

    if dateA not in same_date:
        same_date[dateA] = [variables[idA]]
    else:
        same_date[dateA].append(variables[idA])
    for j in range(i + 1, n_flights):
        flightB = flights[j]
        idB = flightB["id"] + n_cities * 2 - 1
        flightB_date = flightB["date"]
        if idA != idB:
            # If I have left a city, no more flights to that city can exist, except for base.
            if (
                flightA["og_airport"] == flightB["dest_airport"]
                and airport_to_city(flightA["og_airport"])["min_nights"] != 0
            ):
                solver.add(Implies(variables[idA], Not(variables[idB])))
            # If I take a flight to city A, then a flight from city A that is not k nights after can't be true
            min_nightsB = airport_to_city(dest_airport)["min_nights"]
            max_nightsB = airport_to_city(dest_airport)["max_nights"]
            if flightA["dest_airport"] == flightB["og_airport"]:
                if not between_k_nights(
                    flightB["date"], min_nightsB, max_nightsB, flightA["date"]
                ):
                    solver.add(Implies(variables[idA], Not(variables[idB])))


for x in same_og.values():
    solver.add(Sum(x) <= 1)

for x in same_dest.values():
    solver.add(Sum(x) <= 1)

for x in same_date.values():
    solver.add(Sum(x) <= 1)

solver.add(Sum(variables[n_cities * 2 :]) == n_cities)

flight_price_weights = []
for i in range(n_cities * 2, len(variables)):
    price = flights[i - n_cities * 2]["price"]
    flight_price_weights.append(If(variables[i], price, price))

solver.minimize(Sum(flight_price_weights))

# for c in solver.assertions():
#     print(c)


# Function to extract current solution and create a blocking clause
def get_blocking_clause(model, xs):
    return Or([x != model.evaluate(x) for x in xs])


solutions = []
price = []

def pretty_print_solution(solution):
    total_price = 0
    chosen_flights = ""
    for i in range(n_cities * 2, len(variables)):
        if solution[i]:
            flight = flights[i - n_cities * 2]
            date, og_city, dest_city, dep_time, flight_price = (
                flight["date"],
                airport_to_city(flight["og_airport"])["name"],
                airport_to_city(flight["dest_airport"])["name"],
                flight["dep_time"],
                flight["price"],
            )
            total_price += flight["price"]
            chosen_flights += (
                f"{date} {og_city} {dest_city} {dep_time} {flight_price}\n"
            )
    price.append(total_price)
    print(f"{total_price}\n{chosen_flights}".strip())

def process_solutions(solution):
    total_price = 0
    for i in range(n_cities * 2, len(variables)):
        if solution[i]:
            flight = flights[i - n_cities * 2]
            total_price += flight["price"]
    price.append(total_price)

while solver.check() == sat:
    model = solver.model()
    solution = [model.evaluate(x) for x in variables]
    # pretty_print_solution(solution)
    process_solutions(solution)
    solutions.append(solution)
    solver.add(get_blocking_clause(model, variables))

min_solution = price.index(min(price))
pretty_print_solution(solutions[min_solution])
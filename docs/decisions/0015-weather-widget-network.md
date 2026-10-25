# ADR-0015: The weather widget contacts Open-Meteo only after the person enters a city

- Status: Accepted
- Date: 2026-10-25
- Deciders: project owner

## Context

The owner chose desktop widgets including weather (2026-10-25). Weather needs
an online service and a location. Star OS has no location service and should
not send anything by default.

## Options considered

| Option | For | Against |
| --- | --- | --- |
| **Open-Meteo after the person types a city** | Free, no API key, no account; nothing is sent until asked | A third-party service learns the city and the IP address |
| KDE's weather engine (plasma-addons) | Several providers | Private Plasma API; another package |
| No weather widget | No network use | The owner asked for it |

## Decision

The weather widget starts with "Choose a city". When the person enters one,
it asks `geocoding-api.open-meteo.com` for the place and then
`api.open-meteo.com` for the current weather and the day's range, every 30
minutes while the widget is shown. The widget says "Weather from
Open-Meteo" and can be removed. Without network it shows the last values with
their time, or says that it is offline.

## Consequences and trade-offs

- Open-Meteo receives the city name and coordinates and the computer's IP
  address. The widget is off until a city is chosen.
- CI tests the widget with a fake service only.

## Revisit if

- Star OS adds a location service or a privacy setting for online services.

## Approval

- Approved by: project owner (GitHub @Jayyy-tuff), 2026-10-25, choosing
  desktop widgets; the provider awaits review in the M0.5 report.

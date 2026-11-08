# DailyLah Privacy Policy

**Last updated: 8 November 2026**
App: DailyLah (Android, package `com.tursinalabs.dailylah`)
Published at: https://www.tursinalabs.com/dailylah/privacy

## 1. Scope
This policy covers only the DailyLah app by Tursina Labs and its website, dailylah.sg. Other Tursina Labs products are covered by the studio privacy policy. Use of the app is also governed by the [DailyLah Terms of Service](https://www.tursinalabs.com/dailylah/terms).

## 2. What DailyLah is
DailyLah is a free daily companion for people in Singapore. It shows bus arrivals at your saved stops, MRT/LRT service status, platform crowd levels and the 2-hour weather forecast, using public data from LTA DataMall and data.gov.sg. There is no DailyLah account and no sign-in.

## 3. Data stored only on your phone
- Your saved places (Home, Work, School): the address you chose (label, postal code and coordinates) and the bus stops you picked for it
- The MRT/LRT lines you selected, your usual departure times, your alert settings, the days and times you go to work or school, starred MRT lines, and how you usually travel to each place (bus/MRT, car, motorbike, bicycle or taxi), and optional extras
- Favourite hawker centres, saved car parks, and HDB blocks you watch or compare
- Whether your car is electric and its plug type, if you turned on **My car is electric**
- A short log of alerts already shown, so the same alert is not sent twice
- What you choose to log with **Learn my habits**: trips you start and end with "I'm leaving" and "Arrived" (route, start time, minutes, whether it was raining, travel mode and straight-line distance), hawker centres and halal places (name and position) you mark with "Ate here", and the car park, level and lot you save with "I parked here" (and, once you pick the car up, how long you parked there and whether it was an HDB car park, for a cost estimate), and any costs you enter for trips or parking. These are shown on the History tab, where you can remove single entries. You can turn this off and delete it all any time in More > Extras. It is not part of the family share code.
- Copies of public data bundles (bus stops, hawker centres, dengue clusters, schools, parks and their facilities, supermarkets, car parks, HDB blocks, resale and rent statistics, HDB towns by commute and price, prayer times, public and MOE school holidays, public events listed on Eventfinda, and EV charging locations), and the text shown on the home screen widget

This data never leaves your phone. It is not backed up to Tursina Labs, and DailyLah turns off Android backup and phone-to-phone transfer for it, so it is not copied to your Google account or to a new phone. To move your setup to another phone, use **Share with family**.

**Share with family** creates a QR code or text code on your phone containing your saved bus stops, MRT lines and departure times. It is not sent to Tursina Labs; it only leaves your phone if you show it or send it yourself (for example through a chat app). Importing a code works by pasting it, without the camera.

## 4. Location
DailyLah asks for location permission only when you tap **"Nearest stops to my location"**, **"Use my current location"** or **"Here"** in the Nearby tab. Once you have allowed it, the Nearby tab also reads your position when you open it, so it can show what is around you. Your position is used on the phone to find the nearest bus stops, food, car parks, taxis and help, and is then discarded. It is not stored and is not sent to Tursina Labs or anyone else; for live bus arrivals the app sends only the bus stop codes. DailyLah does not otherwise use your location in the background. The exceptions are **"Wake me at my stop"** and **"I'm on the train"**: when you start one during a bus or MRT ride, and you have allowed location, the app follows your position until the ride ends (shown as an ongoing notification, so it keeps working with the screen off), then stops. Your position is compared with the stop or the stations on the phone and is never stored or sent. During an MRT ride the app also asks our server for LTA train alerts every 2 minutes; that request carries no location. You can deny the permission and still pick a saved place or search an address.

## 4a. Address search
When you set an address or search a postal code, the text you type is sent to our server, which passes it on to **OneMap**, the map service of the Singapore Land Authority, with our OneMap account token (OneMap requires one). Our server does not log the search text; it keeps the answer in memory for up to a day so the same search is not repeated, and it never knows who searched. If our server is unavailable, the phone asks OneMap directly. The address you pick is saved only on your phone. You can also choose **"Use my current location"**, which reads your position once and saves it as the address. You can also share a place to DailyLah from another app, such as Google Maps (Share > DailyLah). The shared text is read on your phone and not kept: DailyLah takes the place's name and its postal code (or its coordinates, for a dropped pin), searches only the postal code as above, and uses the place as a trip destination in memory. When only a Google Maps link is shared (for example directions), the phone opens that short link once with Google, which created it, to read the destination's name and pin from the address it leads to; nothing else is sent with it, and the name and the link are never sent to Tursina Labs.

## 5. What our server receives
To show live information, the app sends requests to the DailyLah API operated by Tursina Labs:
- The 5-digit **bus stop code** you are viewing, to get bus arrival times
- If you turned on **My car is electric**, the 6-digit **postal code of an EV charging location** shown in a list, to get how many chargers are free there. This is the car park's postal code from the public LTA list, not yours; which locations are near you is worked out on your phone
- The **MRT/LRT line code** (for example `NSL`), to get platform crowd levels
- A **CEA registration number** you type into "Check a property agent", to look it up in the public CEA register. This number identifies the agent, not you
- Requests for the weather forecast, haze (PSI and PM2.5), heat stress, lightning, train service alerts, HDB car park availability, car park availability for LTA, URA and HDB car parks, traffic incidents and taxi availability, which contain no personal data

Which buses go to your destination, parking near it and incidents on the way are worked out on your phone; the server only sends the full public lists. Searching HDB blocks, comparing blocks, nearby hawker centres, dengue clusters and weekend ideas are all computed on your phone from the public data bundles, so the server does not learn which places you look at.

The app also downloads these public data bundles from our website. Like any web service, our hosting providers record technical request logs (IP address, time, requested path and app version) for operations and security, and keep them for a limited period. We do not combine these logs with any other data and we do not use them to identify you. The server never receives your saved places, home or work location, or GPS coordinates.

The **Home** tab shows your block (or, for a private home, URA sale and rent figures for the project at your address), upgrading and construction work, schools, health and community services, recycling points, parks and parking around your saved home. All of it comes from public data bundles (OneMap, URA and data.gov.sg) downloaded to your phone, and the distances are computed on your phone; your home address is not sent anywhere for this.

On a block's **Prices, rent and score** page, the app also shows the trip from the block's town to an office area, an estimated monthly cost and HDB towns ranked by that trip, from the same public data bundle as the Where to live? page on our website. The office area nearest your saved work or school place is picked on your phone, and your choices (office area, rent or buy, flat type) are kept only on your phone; nothing about them is sent. **More about** a town opens its page on our website in your browser, with only the town's name in the address.

If you turn on **Halal food nearby** (More > Extras), the app shows halal places listed on Muslim.sg from a bundle downloaded to your phone; searching and distances are done on your phone. DailyLah is not affiliated with MUIS.

The **Emergency** tab lists AEDs, A&E hospitals, CHAS clinics, fire stations and Civil Defence shelters near the place you pick, computed on your phone. Tapping a phone number opens your dialer; tapping directions opens Google Maps with the destination only. The "MRT route in Google Maps" button on a trip is the one exception: it opens Google Maps with both ends of that trip (for example your home and your office), and only when you tap it. The taxi view shows free taxis and LTA taxi stands around your place, also computed on your phone. The ride and food delivery buttons (Grab, Gojek, CDG Zig, TADA, GrabFood, foodpanda) only open that app on your phone, or its Play Store page; DailyLah sends nothing to them and takes no orders. Tapping an event opens its page on Eventfinda in your browser; the event list itself is downloaded by our daily build, so Eventfinda never sees who uses DailyLah. When you open a place (a hawker centre, car park, school and so on), the app loads a small map picture of that place from OneMap (Singapore Land Authority); only the place's coordinates are sent, not your location.

## 5a. The dailylah.sg website
The website, including the **Where to live?** page, has no account, no cookies, no analytics and no advertising. On Where to live? your choices (office area, rent or buy, flat type, budget, travel time) are worked out in your browser from a public data file and kept in the page address, so a link you share carries them. When that address is opened or reloaded, it reaches our hosting provider like any page request and appears in its short-lived technical request logs (section 5); we do not use it for anything else and nothing else about your choices is sent. The map on that page loads map tiles and the OneMap logo from **OneMap** (Singapore Land Authority), so OneMap receives your IP address and which map area is shown, as with any website you visit; it does not receive your choices. Our hosting provider keeps the same technical request logs as for the data bundles above.

## 6. Notifications
Alerts for MRT disruptions, rain before your usual departure, favourite hawker centres closing tomorrow, dengue clusters near home or school, high heat stress or lightning, new resale transactions at blocks you watch, when to leave for your bus (to work or school, or to a saved place you gave a usual time), the Sunday "This week around you" summary and your parking time are decided **on your phone**. Every 15 minutes or so, the app checks the latest public alerts and forecast and, if they match your settings, shows a local notification. No push token or device identifier is sent to Tursina Labs. You can turn alerts off in the app settings or in Android settings.

## 7. What we do not do
- No DailyLah account and no sign-in
- No analytics, tracking or advertising SDKs, and no ads
- No sale or sharing of personal information
- No access to your contacts, photos, microphone or camera

## 8. Service providers
- **Render** (Singapore region) hosts the DailyLah API
- **Upstash** caches public weather and transport data (no personal data)
- **Vercel** hosts the public bus stop list and our web pages
- **Google Play** distributes the app and may process install, update and crash data under Google's own policies

Public data comes from **LTA DataMall** and **data.gov.sg**. The app does not send your data to these government sources; our server requests public data on behalf of all users.

## 9. Retention and deletion
Data on your phone stays until you clear the app's storage or uninstall DailyLah. Because there is no account, there is nothing to delete on our side and no account-deletion page. Server request logs expire automatically.

## 10. Your rights
Under Singapore's Personal Data Protection Act (PDPA) you may ask about personal data we hold. Because DailyLah has no accounts and does not link logs to people, we generally cannot identify any request as yours, but you can still contact us with questions.

## 11. Children
DailyLah is not directed at children under 13.

## 12. Changes
We may update this policy. When we do, we change the "Last updated" date above. The current version is always at https://www.tursinalabs.com/dailylah/privacy.

## 13. Contact
support@tursinalabs.com

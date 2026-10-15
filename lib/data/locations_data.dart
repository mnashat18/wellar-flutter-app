class LocationOption {
  final String nameEnglish;
  final String nameArabic;
  final List<LocationOption> children;

  const LocationOption({
    required this.nameEnglish,
    required this.nameArabic,
    this.children = const [],
  });

  String localizedName(bool arabic) => arabic ? nameArabic : nameEnglish;
}

class CascadingLocationSelection {
  LocationOption? country;
  LocationOption? region;
  LocationOption? city;

  void selectCountry(LocationOption? value) {
    country = value;
    region = null;
    city = null;
  }

  void selectRegion(LocationOption? value) {
    region = value;
    city = null;
  }

  void selectCity(LocationOption? value) => city = value;
}

class LocationsData {
  static final List<LocationOption> countries = List.unmodifiable([
    _country('Egypt', 'مصر', '''
Cairo^القاهرة:Cairo~القاهرة;New Cairo~القاهرة الجديدة;Heliopolis~مصر الجديدة;Nasr City~مدينة نصر;Shubra~شبرا
Giza^الجيزة:Giza~الجيزة;6th of October~السادس من أكتوبر;Sheikh Zayed~الشيخ زايد;Hawamdeya~الحوامدية
Alexandria^الإسكندرية:Alexandria~الإسكندرية;Borg El Arab~برج العرب;Abu Qir~أبو قير
Qalyubia^القليوبية:Banha~بنها;Shubra El Kheima~شبرا الخيمة;Qalyub~قليوب;Obour~العبور
Dakahlia^الدقهلية:Mansoura~المنصورة;Mit Ghamr~ميت غمر;Talkha~طلخا;Dikirnis~دكرنس
Sharqia^الشرقية:Zagazig~الزقازيق;10th of Ramadan~العاشر من رمضان;Belbeis~بلبيس;Abu Hammad~أبو حماد
Gharbia^الغربية:Tanta~طنطا;El Mahalla El Kubra~المحلة الكبرى;Zefta~زفتى;Kafr El Zayat~كفر الزيات
Monufia^المنوفية:Shebin El Kom~شبين الكوم;Menouf~منوف;Ashmoun~أشمون;Sadat City~مدينة السادات
Beheira^البحيرة:Damanhur~دمنهور;Kafr El Dawwar~كفر الدوار;Rashid~رشيد;Edko~إدكو
Kafr El Sheikh^كفر الشيخ:Kafr El Sheikh~كفر الشيخ;Desouk~دسوق;Baltim~بلطيم;Sidi Salem~سيدي سالم
Damietta^دمياط:Damietta~دمياط;New Damietta~دمياط الجديدة;Faraskur~فارسكور;Kafr Saad~كفر سعد
Port Said^بورسعيد:Port Said~بورسعيد;Port Fouad~بورفؤاد
Ismailia^الإسماعيلية:Ismailia~الإسماعيلية;Fayed~فايد;Qantara East~القنطرة شرق
Suez^السويس:Suez~السويس;Ain Sokhna~العين السخنة
North Sinai^شمال سيناء:Arish~العريش;Bir al-Abed~بئر العبد;Rafah~رفح;Sheikh Zuweid~الشيخ زويد
South Sinai^جنوب سيناء:Sharm El Sheikh~شرم الشيخ;Dahab~دهب;Nuweiba~نويبع;El Tor~الطور
Red Sea^البحر الأحمر:Hurghada~الغردقة;Safaga~سفاجا;Marsa Alam~مرسى علم;Ras Gharib~رأس غارب
New Valley^الوادي الجديد:Kharga~الخارجة;Dakhla~الداخلة;Farafra~الفرافرة;Balat~بلاط
Matrouh^مطروح:Marsa Matrouh~مرسى مطروح;El Alamein~العلمين;Siwa~سيوة;Sallum~السلوم
Faiyum^الفيوم:Faiyum~الفيوم;Sinnuris~سنورس;Ibsheway~إبشواي;Tamiya~طامية
Beni Suef^بني سويف:Beni Suef~بني سويف;Biba~ببا;Nasser~ناصر;Ihnasia~إهناسيا
Minya^المنيا:Minya~المنيا;Mallawi~ملوي;Samalut~سمالوط;Abu Qurqas~أبو قرقاص
Assiut^أسيوط:Assiut~أسيوط;Abnoub~أبنوب;Manfalut~منفلوط;Dairut~ديروط
Sohag^سوهاج:Sohag~سوهاج;Akhmim~أخميم;Girga~جرجا;Tahta~طهطا
Qena^قنا:Qena~قنا;Nag Hammadi~نجع حمادي;Qus~قوص;Dishna~دشنا
Luxor^الأقصر:Luxor~الأقصر;Esna~إسنا;Armant~أرمنت;Tiba~طيبة
Aswan^أسوان:Aswan~أسوان;Kom Ombo~كوم أمبو;Edfu~إدفو;Abu Simbel~أبو سمبل
'''),
    _country('Saudi Arabia', 'السعودية', '''
Riyadh^الرياض:Riyadh~الرياض;Diriyah~الدرعية;Al Kharj~الخرج
Makkah^مكة المكرمة:Makkah~مكة;Jeddah~جدة;Taif~الطائف
Madinah^المدينة المنورة:Madinah~المدينة المنورة;Yanbu~ينبع;Al Ula~العلا
Eastern Province^المنطقة الشرقية:Dammam~الدمام;Al Khobar~الخبر;Dhahran~الظهران;Jubail~الجبيل
Qassim^القصيم:Buraydah~بريدة;Unaizah~عنيزة;Al Rass~الرس
Hail^حائل:Hail~حائل;Baqaa~بقعاء
Tabuk^تبوك:Tabuk~تبوك;Tayma~تيماء;Umluj~أملج
Northern Borders^الحدود الشمالية:Arar~عرعر;Rafha~رفحاء;Turaif~طريف
Jazan^جازان:Jazan~جازان;Sabya~صبيا;Abu Arish~أبو عريش
Najran^نجران:Najran~نجران;Sharurah~شرورة
Al Bahah^الباحة:Al Bahah~الباحة;Baljurashi~بلجرشي
Al Jawf^الجوف:Sakaka~سكاكا;Dumat Al Jandal~دومة الجندل
Asir^عسير:Abha~أبها;Khamis Mushait~خميس مشيط;Bisha~بيشة
'''),
    _country('United Arab Emirates', 'الإمارات العربية المتحدة', '''
Abu Dhabi^أبوظبي:Abu Dhabi~أبوظبي;Al Ain~العين;Al Dhafra~الظفرة
Dubai^دبي:Dubai~دبي;Hatta~حتا
Sharjah^الشارقة:Sharjah~الشارقة;Khor Fakkan~خورفكان;Kalba~كلباء
Ajman^عجمان:Ajman~عجمان;Manama~المنامة
Umm Al Quwain^أم القيوين:Umm Al Quwain~أم القيوين
Ras Al Khaimah^رأس الخيمة:Ras Al Khaimah~رأس الخيمة;Al Jazirah Al Hamra~الجزيرة الحمراء
Fujairah^الفجيرة:Fujairah~الفجيرة;Dibba Al Fujairah~دبا الفجيرة
'''),
    _country('Kuwait', 'الكويت', '''
Capital^العاصمة:Kuwait City~مدينة الكويت
Hawalli^حولي:Hawalli~حولي;Salmiya~السالمية
Farwaniya^الفروانية:Farwaniya~الفروانية;Jleeb Al-Shuyoukh~جليب الشيوخ
Mubarak Al-Kabeer^مبارك الكبير:Mubarak Al-Kabeer~مبارك الكبير;Abu Al Hasaniya~أبو الحصانية
Ahmadi^الأحمدي:Ahmadi~الأحمدي;Fahaheel~الفحيحيل;Mangaf~المنقف
Jahra^الجهراء:Jahra~الجهراء;Sulaibiya~الصليبية
'''),
    _country('Qatar', 'قطر', '''
Doha^الدوحة:Doha~الدوحة;Lusail~لوسيل
Al Rayyan^الريان:Al Rayyan~الريان;Education City~المدينة التعليمية
Al Wakrah^الوكرة:Al Wakrah~الوكرة;Mesaieed~مسيعيد
Al Daayen^الضعاين:Al Daayen~الضعاين;Lusail~لوسيل
Umm Salal^أم صلال:Umm Salal Mohammed~أم صلال محمد
Al Khor and Al Thakhira^الخور والذخيرة:Al Khor~الخور;Al Thakhira~الذخيرة
Al Shamal^الشمال:Madinat ash Shamal~مدينة الشمال
Al Shahaniya^الشحانية:Al Shahaniya~الشحانية
'''),
    _country('Bahrain', 'البحرين', '''
Capital^العاصمة:Manama~المنامة;Juffair~الجفير
Muharraq^المحرق:Muharraq~المحرق;Hidd~الحد
Northern^الشمالية:Hamad Town~مدينة حمد;Budaiya~البديع
Southern^الجنوبية:Riffa~الرفاع;Isa Town~مدينة عيسى;Zallaq~الزلاق
'''),
    _country('Oman', 'عُمان', '''
Muscat^مسقط:Muscat~مسقط;Seeb~السيب;Muttrah~مطرح
Dhofar^ظفار:Salalah~صلالة;Mirbat~مرباط
Musandam^مسندم:Khasab~خصب;Dibba~دبا
Al Buraimi^البريمي:Al Buraimi~البريمي;Mahdah~محضة
Ad Dakhiliyah^الداخلية:Nizwa~نزوى;Bahla~بهلاء;Samail~سمائل
North Al Batinah^شمال الباطنة:Sohar~صحار;Shinas~شناص;Liwa~لوى
South Al Batinah^جنوب الباطنة:Rustaq~الرستاق;Barka~بركاء;Nakhal~نخل
North Ash Sharqiyah^شمال الشرقية:Ibra~إبراء;Bidiyah~بدية;Al Mudhaibi~المضيبي
South Ash Sharqiyah^جنوب الشرقية:Sur~صور;Jalan Bani Bu Ali~جعلان بني بو علي
Al Dhahirah^الظاهرة:Ibri~عبري;Yanqul~ينقل
Al Wusta^الوسطى:Haima~هيماء;Duqm~الدقم
'''),
    _country('Jordan', 'الأردن', '''
Amman^عمّان:Amman~عمّان;Sahab~سحاب;Naour~ناعور
Irbid^إربد:Irbid~إربد;Ramtha~الرمثا;Mafraq~المفرق
Zarqa^الزرقاء:Zarqa~الزرقاء;Russeifa~الرصيفة
Balqa^البلقاء:Salt~السلط;Ain Al Basha~عين الباشا
Madaba^مادبا:Madaba~مادبا;Dhiban~ذيبان
Karak^الكرك:Karak~الكرك;Mazar~المزار
Tafilah^الطفيلة:Tafilah~الطفيلة;Busaira~بصيرا
Ma'an^معان:Ma'an~معان;Petra~البتراء;Wadi Musa~وادي موسى
Aqaba^العقبة:Aqaba~العقبة;Quweira~القويرة
Mafraq^المفرق:Mafraq~المفرق;Rehab~الرحاب
Jerash^جرش:Jerash~جرش;Sakib~ساكب
Ajloun^عجلون:Ajloun~عجلون;Anjara~عنجرة
'''),
    _country('Lebanon', 'لبنان', '''
Beirut^بيروت:Beirut~بيروت
Mount Lebanon^جبل لبنان:Jounieh~جونية;Baabda~بعبدا;Aley~عاليه
North Lebanon^الشمال:Tripoli~طرابلس;Zgharta~زغرتا;Batroun~البترون
Akkar^عكار:Halba~حلبا;Qoubaiyat~القبيات
Baalbek-Hermel^بعلبك الهرمل:Baalbek~بعلبك;Hermel~الهرمل
Bekaa^البقاع:Zahle~زحلة;West Bekaa~البقاع الغربي
Nabatieh^النبطية:Nabatieh~النبطية;Bint Jbeil~بنت جبيل
South Lebanon^الجنوب:Sidon~صيدا;Tyre~صور;Jezzine~جزين
'''),
    _country('Iraq', 'العراق', '''
Baghdad^بغداد:Baghdad~بغداد
Basra^البصرة:Basra~البصرة;Zubair~الزبير
Nineveh^نينوى:Mosul~الموصل;Tal Afar~تلعفر
Erbil^أربيل:Erbil~أربيل;Soran~سوران
Sulaymaniyah^السليمانية:Sulaymaniyah~السليمانية;Halabja~حلبجة
Dohuk^دهوك:Dohuk~دهوك;Zakho~زاخو
Kirkuk^كركوك:Kirkuk~كركوك
Anbar^الأنبار:Ramadi~الرمادي;Fallujah~الفلوجة
Najaf^النجف:Najaf~النجف;Kufa~الكوفة
Karbala^كربلاء:Karbala~كربلاء
Babil^بابل:Hilla~الحلة;Musayyib~المسيب
Wasit^واسط:Kut~الكوت;Al Hayy~الحي
Maysan^ميسان:Amarah~العمارة;Ali Al Gharbi~علي الغربي
Dhi Qar^ذي قار:Nasiriyah~الناصرية;Al Shatrah~الشطرة
Muthanna^المثنى:Samawah~السماوة;Rumaitha~الرميثة
Qadisiyyah^القادسية:Diwaniyah~الديوانية;Afak~عفك
Diyala^ديالى:Baqubah~بعقوبة;Khanaqin~خانقين
Saladin^صلاح الدين:Tikrit~تكريت;Samarra~سامراء
'''),
    _country('Libya', 'ليبيا', '''
Tripoli^طرابلس:Tripoli~طرابلس;Tajura~تاجوراء
Benghazi^بنغازي:Benghazi~بنغازي;Al Marj~المرج
Misrata^مصراتة:Misrata~مصراتة;Zliten~زليتن
Zawiya^الزاوية:Zawiya~الزاوية;Sabratha~صبراتة
Jabal al Gharbi^الجبل الغربي:Gharyan~غريان;Yefren~يفرن
Jafara^الجفارة:Aziziyah~العزيزية;Janzur~جنزور
Murqub^المرقب:Khums~الخمس;Tarhuna~ترهونة
Nalut^نالوت:Nalut~نالوت;Ghadames~غدامس
Nuqat al Khams^النقاط الخمس:Zuwara~زوارة;Riqdalin~رقدالين
Al Jabal al Akhdar^الجبل الأخضر:Bayda~البيضاء;Shahhat~شحات
Derna^درنة:Derna~درنة;Qubbah~القبة
Al Wahat^الواحات:Ajdabiya~أجدابيا;Jalu~جالو
Al Marj^المرج:Marj~المرج;Tocra~توكرة
Al Butnan^البطنان:Tobruk~طبرق;Bardia~البردية
Ghat^غات:Ghat~غات;Awainat~العوينات
Murzuq^مرزق:Murzuq~مرزق;Qatrun~القطرون
Sabha^سبها:Sabha~سبها;Brak~براك
Wadi al Hayaa^وادي الحياة:Ubari~أوباري;Ghat~غات
Wadi al Shatii^وادي الشاطئ:Brak~براك;Idri~إدري
Sirte^سرت:Sirte~سرت;Bin Jawad~بن جواد
Al Jufra^الجفرة:Houn~هون;Waddan~ودان
Al Kufra^الكفرة:Kufra~الكفرة;Rebiana~ربيانة
'''),
    _country('Morocco', 'المغرب', '''
Tangier-Tetouan-Al Hoceima^طنجة تطوان الحسيمة:Tangier~طنجة;Tetouan~تطوان;Al Hoceima~الحسيمة
Oriental^الشرق:Oujda~وجدة;Nador~الناظور;Berkane~بركان
Fes-Meknes^فاس مكناس:Fes~فاس;Meknes~مكناس;Taza~تازة
Rabat-Sale-Kenitra^الرباط سلا القنيطرة:Rabat~الرباط;Sale~سلا;Kenitra~القنيطرة
Beni Mellal-Khenifra^بني ملال خنيفرة:Beni Mellal~بني ملال;Khouribga~خريبكة
Casablanca-Settat^الدار البيضاء سطات:Casablanca~الدار البيضاء;Settat~سطات;El Jadida~الجديدة
Marrakech-Safi^مراكش آسفي:Marrakech~مراكش;Safi~آسفي;Essaouira~الصويرة
Draa-Tafilalet^درعة تافيلالت:Errachidia~الرشيدية;Ouarzazate~ورزازات
Souss-Massa^سوس ماسة:Agadir~أكادير;Taroudant~تارودانت;Tiznit~تزنيت
Guelmim-Oued Noun^كلميم واد نون:Guelmim~كلميم;Tan-Tan~طانطان
Laayoune-Sakia El Hamra^العيون الساقية الحمراء:Laayoune~العيون;Boujdour~بوجدور
Dakhla-Oued Ed-Dahab^الداخلة وادي الذهب:Dakhla~الداخلة;Aousserd~أوسرد
'''),
    _country('Algeria', 'الجزائر', '''
Adrar^أدرار:Adrar~أدرار
Chlef^الشلف:Chlef~الشلف
Laghouat^الأغواط:Laghouat~الأغواط
Oum El Bouaghi^أم البواقي:Oum El Bouaghi~أم البواقي
Batna^باتنة:Batna~باتنة
Bejaia^بجاية:Bejaia~بجاية
Biskra^بسكرة:Biskra~بسكرة
Bechar^بشار:Bechar~بشار
Blida^البليدة:Blida~البليدة
Bouira^البويرة:Bouira~البويرة
Tamanrasset^تمنراست:Tamanrasset~تمنراست
Tebessa^تبسة:Tebessa~تبسة
Tlemcen^تلمسان:Tlemcen~تلمسان
Tiaret^تيارت:Tiaret~تيارت
Tizi Ouzou^تيزي وزو:Tizi Ouzou~تيزي وزو
Algiers^الجزائر العاصمة:Algiers~الجزائر
Djelfa^الجلفة:Djelfa~الجلفة
Jijel^جيجل:Jijel~جيجل
Setif^سطيف:Setif~سطيف
Saida^سعيدة:Saida~سعيدة
Skikda^سكيكدة:Skikda~سكيكدة
Sidi Bel Abbes^سيدي بلعباس:Sidi Bel Abbes~سيدي بلعباس
Annaba^عنابة:Annaba~عنابة
Guelma^قالمة:Guelma~قالمة
Constantine^قسنطينة:Constantine~قسنطينة
Medea^المدية:Medea~المدية
Mostaganem^مستغانم:Mostaganem~مستغانم
M'Sila^المسيلة:M'Sila~المسيلة
Mascara^معسكر:Mascara~معسكر
Ouargla^ورقلة:Ouargla~ورقلة
Oran^وهران:Oran~وهران
El Bayadh^البيض:El Bayadh~البيض
Illizi^إليزي:Illizi~إليزي
Bordj Bou Arreridj^برج بوعريريج:Bordj Bou Arreridj~برج بوعريريج
Boumerdes^بومرداس:Boumerdes~بومرداس
El Tarf^الطارف:El Tarf~الطارف
Tindouf^تندوف:Tindouf~تندوف
Tissemsilt^تيسمسيلت:Tissemsilt~تيسمسيلت
El Oued^الوادي:El Oued~الوادي
Khenchela^خنشلة:Khenchela~خنشلة
Souk Ahras^سوق أهراس:Souk Ahras~سوق أهراس
Tipaza^تيبازة:Tipaza~تيبازة
Mila^ميلة:Mila~ميلة
Ain Defla^عين الدفلى:Ain Defla~عين الدفلى
Naama^النعامة:Naama~النعامة
Ain Temouchent^عين تموشنت:Ain Temouchent~عين تموشنت
Ghardaia^غرداية:Ghardaia~غرداية
Relizane^غليزان:Relizane~غليزان
Timimoun^تيميمون:Timimoun~تيميمون
Bordj Badji Mokhtar^برج باجي مختار:Bordj Badji Mokhtar~برج باجي مختار
Ouled Djellal^أولاد جلال:Ouled Djellal~أولاد جلال
Beni Abbes^بني عباس:Beni Abbes~بني عباس
In Salah^عين صالح:In Salah~عين صالح
In Guezzam^عين قزام:In Guezzam~عين قزام
Touggourt^تقرت:Touggourt~تقرت
Djanet^جانت:Djanet~جانت
El M'Ghair^المغير:El M'Ghair~المغير
El Meniaa^المنيعة:El Meniaa~المنيعة
'''),
    _country('Tunisia', 'تونس', '''
Tunis^تونس:Tunis~تونس;La Marsa~المرسى
Ariana^أريانة:Ariana~أريانة
Ben Arous^بن عروس:Ben Arous~بن عروس
Manouba^منوبة:Manouba~منوبة
Nabeul^نابل:Nabeul~نابل;Hammamet~الحمامات
Zaghouan^زغوان:Zaghouan~زغوان
Bizerte^بنزرت:Bizerte~بنزرت
Beja^باجة:Beja~باجة
Jendouba^جندوبة:Jendouba~جندوبة;Tabarka~طبرقة
Kef^الكاف:Kef~الكاف
Siliana^سليانة:Siliana~سليانة
Sousse^سوسة:Sousse~سوسة;Msaken~مساكن
Monastir^المنستير:Monastir~المنستير
Mahdia^المهدية:Mahdia~المهدية
Sfax^صفاقس:Sfax~صفاقس
Kairouan^القيروان:Kairouan~القيروان
Kasserine^القصرين:Kasserine~القصرين
Sidi Bouzid^سيدي بوزيد:Sidi Bouzid~سيدي بوزيد
Gabes^قابس:Gabes~قابس
Medenine^مدنين:Medenine~مدنين;Djerba~جربة
Tataouine^تطاوين:Tataouine~تطاوين
Gafsa^قفصة:Gafsa~قفصة
Tozeur^توزر:Tozeur~توزر
Kebili^قبلي:Kebili~قبلي
'''),
    _country('Sudan', 'السودان', '''
Khartoum^الخرطوم:Khartoum~الخرطوم;Omdurman~أم درمان;Khartoum North~الخرطوم بحري
Gezira^الجزيرة:Wad Madani~ود مدني
Red Sea^البحر الأحمر:Port Sudan~بورتسودان
Kassala^كسلا:Kassala~كسلا
Gedaref^القضارف:Gedaref~القضارف
Sennar^سنار:Sennar~سنار;Singa~سنجة
Blue Nile^النيل الأزرق:Ad-Damazin~الدمازين
White Nile^النيل الأبيض:Kosti~كوستي;Rabak~ربك
North Kordofan^شمال كردفان:El Obeid~الأبيض
South Kordofan^جنوب كردفان:Kadugli~كادوقلي
West Kordofan^غرب كردفان:An Nuhud~النهود
North Darfur^شمال دارفور:El Fasher~الفاشر
South Darfur^جنوب دارفور:Nyala~نيالا
West Darfur^غرب دارفور:Geneina~الجنينة
Central Darfur^وسط دارفور:Zalingei~زالنجي
East Darfur^شرق دارفور:Ed Daein~الضعين
River Nile^نهر النيل:Atbara~عطبرة;Ad-Damir~الدامر
Northern^الشمالية:Dongola~دنقلا;Wadi Halfa~وادي حلفا
'''),
    _country('United States', 'الولايات المتحدة', '''
Alabama^ألاباما:Birmingham~برمنغهام
Alaska^ألاسكا:Anchorage~أنكوريج
Arizona^أريزونا:Phoenix~فينيكس
Arkansas^أركنساس:Little Rock~ليتل روك
California^كاليفورنيا:Los Angeles~لوس أنجلوس;San Francisco~سان فرانسيسكو
Colorado^كولورادو:Denver~دنفر
Connecticut^كونيتيكت:Hartford~هارتفورد
Delaware^ديلاوير:Wilmington~ويلمنغتون
Florida^فلوريدا:Miami~ميامي;Orlando~أورلاندو
Georgia^جورجيا:Atlanta~أتلانتا
Hawaii^هاواي:Honolulu~هونولولو
Idaho^أيداهو:Boise~بويزي
Illinois^إلينوي:Chicago~شيكاغو
Indiana^إنديانا:Indianapolis~إنديانابوليس
Iowa^آيوا:Des Moines~دي موين
Kansas^كانساس:Wichita~ويتشيتا
Kentucky^كنتاكي:Louisville~لويفيل
Louisiana^لويزيانا:New Orleans~نيو أورلينز
Maine^مين:Portland~بورتلاند
Maryland^ماريلاند:Baltimore~بالتيمور
Massachusetts^ماساتشوستس:Boston~بوسطن
Michigan^ميشيغان:Detroit~ديترويت
Minnesota^مينيسوتا:Minneapolis~مينيابوليس
Mississippi^ميسيسيبي:Jackson~جاكسون
Missouri^ميزوري:Kansas City~كانساس سيتي
Montana^مونتانا:Billings~بيلينغز
Nebraska^نبراسكا:Omaha~أوماها
Nevada^نيفادا:Las Vegas~لاس فيغاس
New Hampshire^نيوهامبشير:Manchester~مانشستر
New Jersey^نيوجيرسي:Newark~نيوارك
New Mexico^نيومكسيكو:Albuquerque~ألباكركي
New York^نيويورك:New York City~مدينة نيويورك;Buffalo~بافالو
North Carolina^كارولاينا الشمالية:Charlotte~شارلوت
North Dakota^داكوتا الشمالية:Fargo~فارغو
Ohio^أوهايو:Columbus~كولومبوس
Oklahoma^أوكلاهوما:Oklahoma City~أوكلاهوما سيتي
Oregon^أوريغون:Portland~بورتلاند
Pennsylvania^بنسلفانيا:Philadelphia~فيلادلفيا;Pittsburgh~بيتسبرغ
Rhode Island^رود آيلاند:Providence~بروفيدنس
South Carolina^كارولاينا الجنوبية:Charleston~تشارلستون
South Dakota^داكوتا الجنوبية:Sioux Falls~سيوكس فولز
Tennessee^تينيسي:Nashville~ناشفيل
Texas^تكساس:Houston~هيوستن;Dallas~دالاس;Austin~أوستن
Utah^يوتا:Salt Lake City~سولت ليك سيتي
Vermont^فيرمونت:Burlington~برلينغتون
Virginia^فرجينيا:Virginia Beach~فيرجينيا بيتش;Richmond~ريتشموند
Washington^واشنطن:Seattle~سياتل
West Virginia^فرجينيا الغربية:Charleston~تشارلستون
Wisconsin^ويسكونسن:Milwaukee~ميلووكي
Wyoming^وايومنغ:Cheyenne~شايان
District of Columbia^مقاطعة كولومبيا:Washington~واشنطن
'''),
    _country('United Kingdom', 'المملكة المتحدة', '''
England^إنجلترا:London~لندن;Manchester~مانشستر;Birmingham~برمنغهام
Scotland^اسكتلندا:Edinburgh~إدنبرة;Glasgow~غلاسكو
Wales^ويلز:Cardiff~كارديف;Swansea~سوانزي
Northern Ireland^أيرلندا الشمالية:Belfast~بلفاست;Derry~ديري
'''),
    _country('Canada', 'كندا', '''
Alberta^ألبرتا:Calgary~كالغاري;Edmonton~إدمونتون
British Columbia^كولومبيا البريطانية:Vancouver~فانكوفر;Victoria~فيكتوريا
Manitoba^مانيتوبا:Winnipeg~وينيبيغ
New Brunswick^نيو برونزويك:Moncton~مونكتون;Fredericton~فريدريكتون
Newfoundland and Labrador^نيوفاوندلاند ولابرادور:St. John's~سانت جونز
Northwest Territories^الأقاليم الشمالية الغربية:Yellowknife~يلو نايف
Nova Scotia^نوفا سكوشا:Halifax~هاليفاكس
Nunavut^نونافوت:Iqaluit~إيكالويت
Ontario^أونتاريو:Toronto~تورونتو;Ottawa~أوتاوا
Prince Edward Island^جزيرة الأمير إدوارد:Charlottetown~شارلوت تاون
Quebec^كيبيك:Montreal~مونتريال;Quebec City~مدينة كيبيك
Saskatchewan^ساسكاتشوان:Saskatoon~ساسكاتون;Regina~ريجاينا
Yukon^يوكون:Whitehorse~وايت هورس
'''),
    _country('Germany', 'ألمانيا', '''
Baden-Wurttemberg^بادن فورتمبيرغ:Stuttgart~شتوتغارت
Bavaria^بافاريا:Munich~ميونخ;Nuremberg~نورمبرغ
Berlin^برلين:Berlin~برلين
Brandenburg^براندنبورغ:Potsdam~بوتسدام
Bremen^بريمن:Bremen~بريمن
Hamburg^هامبورغ:Hamburg~هامبورغ
Hesse^هيسن:Frankfurt~فرانكفورت;Wiesbaden~فيسبادن
Lower Saxony^ساكسونيا السفلى:Hanover~هانوفر
Mecklenburg-Vorpommern^مكلنبورغ فوربومرن:Rostock~روستوك
North Rhine-Westphalia^شمال الراين وستفاليا:Cologne~كولونيا;Dusseldorf~دوسلدورف
Rhineland-Palatinate^راينلاند بفالتس:Mainz~ماينز
Saarland^سارلاند:Saarbrucken~زاربروكن
Saxony^ساكسونيا:Dresden~درسدن;Leipzig~لايبزيغ
Saxony-Anhalt^ساكسونيا أنهالت:Magdeburg~ماغديبورغ
Schleswig-Holstein^شليسفيغ هولشتاين:Kiel~كيل
Thuringia^تورينغن:Erfurt~إرفورت
'''),
    _country('France', 'فرنسا', '''
Auvergne-Rhone-Alpes^أوفرن رون ألب:Lyon~ليون;Grenoble~غرونوبل
Bourgogne-Franche-Comte^بورغون فرانش كومتي:Dijon~ديجون;Besancon~بيزانسون
Brittany^بريتاني:Rennes~رين;Brest~بريست
Centre-Val de Loire^سنتر فال دو لوار:Orleans~أورليان;Tours~تور
Corsica^كورسيكا:Ajaccio~أجاكسيو;Bastia~باستيا
Grand Est^غراند إيست:Strasbourg~ستراسبورغ;Reims~ريمس
Hauts-de-France^أو دو فرانس:Lille~ليل;Amiens~أميان
Ile-de-France^إيل دو فرانس:Paris~باريس;Versailles~فرساي
Normandy^نورماندي:Rouen~روان;Caen~كاين
Nouvelle-Aquitaine^نوفيل آكيتين:Bordeaux~بوردو;Limoges~ليموج
Occitanie^أوكسيتاني:Toulouse~تولوز;Montpellier~مونبلييه
Pays de la Loire^باي دو لا لوار:Nantes~نانت;Angers~أنجيه
Provence-Alpes-Cote d'Azur^بروفانس ألب كوت دازور:Marseille~مرسيليا;Nice~نيس
Guadeloupe^غوادلوب:Basse-Terre~باس تير;Pointe-a-Pitre~بوانت آ بيتر
Martinique^مارتينيك:Fort-de-France~فور دو فرانس
French Guiana^غويانا الفرنسية:Cayenne~كايين
Reunion^ريونيون:Saint-Denis~سان دوني
Mayotte^مايوت:Mamoudzou~مامودزو
'''),
  ]);

  static LocationOption? countryNamed(String name) {
    for (final country in countries) {
      if (country.nameEnglish == name || country.nameArabic == name) {
        return country;
      }
    }
    return null;
  }

  static LocationOption? childNamed(List<LocationOption> options, String name) {
    for (final option in options) {
      if (option.nameEnglish == name || option.nameArabic == name) {
        return option;
      }
    }
    return null;
  }
}

LocationOption _country(String nameEnglish, String nameArabic, String data) {
  final regions = <LocationOption>[];
  for (final line in data.trim().split('\n')) {
    final entry = line.trim();
    if (entry.isEmpty) continue;
    final divider = entry.indexOf(':');
    if (divider < 0) continue;
    final names = entry.substring(0, divider).split('^');
    if (names.length != 2) continue;
    final cities = <LocationOption>[];
    for (final pair in entry.substring(divider + 1).split(';')) {
      final cityNames = pair.split('~');
      if (cityNames.length == 2) {
        cities.add(
          LocationOption(nameEnglish: cityNames[0], nameArabic: cityNames[1]),
        );
      }
    }
    regions.add(
      LocationOption(
        nameEnglish: names[0],
        nameArabic: names[1],
        children: List.unmodifiable(cities),
      ),
    );
  }
  return LocationOption(
    nameEnglish: nameEnglish,
    nameArabic: nameArabic,
    children: List.unmodifiable(regions),
  );
}

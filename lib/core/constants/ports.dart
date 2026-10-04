/// Indian seaports, inland container depots and CFS hubs for import/export
/// loads. `place` is what goes into a pickup/drop field; it names a city
/// the offline distance table knows where possible.
enum TradeHubKind { port, icd, cfs }

class TradeHub {
  final String code;
  final String name;
  final String city;
  final TradeHubKind kind;

  const TradeHub(this.code, this.name, this.city, this.kind);

  String get place => '$name, $city';
}

const List<TradeHub> tradeHubs = [
  TradeHub('INNSA', 'JNPT (Nhava Sheva)', 'Navi Mumbai', TradeHubKind.port),
  TradeHub('INMUN', 'Mundra Port', 'Mundra', TradeHubKind.port),
  TradeHub('INMAA', 'Chennai Port', 'Chennai', TradeHubKind.port),
  TradeHub('INENR', 'Kamarajar (Ennore) Port', 'Chennai', TradeHubKind.port),
  TradeHub('INCCU', 'Kolkata Port', 'Kolkata', TradeHubKind.port),
  TradeHub('INVTZ', 'Visakhapatnam Port', 'Visakhapatnam', TradeHubKind.port),
  TradeHub('INCOK', 'Cochin Port (Vallarpadam)', 'Kochi', TradeHubKind.port),
  TradeHub('INTUT', 'V.O. Chidambaranar Port', 'Tuticorin', TradeHubKind.port),
  TradeHub('INIXY', 'Kandla (Deendayal) Port', 'Kandla', TradeHubKind.port),
  TradeHub('INMAA2', 'Pipavav Port', 'Rajkot', TradeHubKind.port),
  TradeHub('INHZR', 'Hazira Port', 'Surat', TradeHubKind.port),
  TradeHub('INIXE', 'New Mangalore Port', 'Mangaluru', TradeHubKind.port),
  TradeHub('INKRI', 'Krishnapatnam Port', 'Vijayawada', TradeHubKind.port),
  TradeHub('INDEL4', 'ICD Tughlakabad', 'Delhi', TradeHubKind.icd),
  TradeHub('INDEL5', 'ICD Patparganj', 'Delhi', TradeHubKind.icd),
  TradeHub('INDAD', 'ICD Dadri', 'Noida', TradeHubKind.icd),
  TradeHub('INLDH', 'ICD Ludhiana (Dhandari Kalan)', 'Ludhiana', TradeHubKind.icd),
  TradeHub('INSAB', 'ICD Khodiyar', 'Ahmedabad', TradeHubKind.icd),
  TradeHub('INBLR', 'ICD Whitefield', 'Bengaluru', TradeHubKind.icd),
  TradeHub('INHYD', 'ICD Hyderabad (Sanathnagar)', 'Hyderabad', TradeHubKind.icd),
  TradeHub('INJAI', 'ICD Jaipur (Kanakpura)', 'Jaipur', TradeHubKind.icd),
  TradeHub('INKNU', 'ICD Dadanagar', 'Kanpur', TradeHubKind.icd),
  TradeHub('INNAG', 'ICD Nagpur (MIHAN)', 'Nagpur', TradeHubKind.icd),
  TradeHub('INPNQ', 'ICD Pune (Talegaon)', 'Pune', TradeHubKind.icd),
  TradeHub('CFSNSA', 'CFS Nhava Sheva (Uran)', 'Navi Mumbai', TradeHubKind.cfs),
  TradeHub('CFSMAA', 'CFS Chennai (Manali)', 'Chennai', TradeHubKind.cfs),
  TradeHub('CFSMUN', 'CFS Mundra', 'Mundra', TradeHubKind.cfs),
  TradeHub('CFSCCU', 'CFS Kolkata (Garden Reach)', 'Kolkata', TradeHubKind.cfs),
];

/// Hubs whose name, code or city contains [query] (case-insensitive); all
/// hubs for an empty query.
List<TradeHub> searchHubs(String query, {TradeHubKind? kind}) {
  final q = query.trim().toLowerCase();
  return [
    for (final h in tradeHubs)
      if ((kind == null || h.kind == kind) &&
          (q.isEmpty || h.name.toLowerCase().contains(q) || h.city.toLowerCase().contains(q) || h.code.toLowerCase().contains(q)))
        h,
  ];
}

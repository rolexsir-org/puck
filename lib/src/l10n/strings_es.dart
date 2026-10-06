/// Spanish.
///
/// Written to be *read by a person in a hurry*, not to be a literal rendering
/// of the English. Two rules were applied throughout:
///
///   * Informal address (`tú`, not `usted`). Puck is a tool someone holds in
///     one hand at a bus stop; `usted` is what a bank calls you.
///   * Terse. The card is small and the glance is short, so the strings are
///     shorter than a translation would normally be -- "Toca — lo importante"
///     rather than "Toca para ver la única cosa que merece la pena saber".
///
/// Regional note: this is neutral Spanish (no `vosotros`, no regionalisms),
/// which reads naturally in both Spain and Latin America.
const Map<String, String> stringsEs = <String, String>{
  'bubbleLabel': 'Puck',
  'bubbleHint': 'Toca para lo importante. Doble toque para un chiste. '
      'Mantén pulsado para emergencias. Desliza hacia arriba para preguntar.',
  'actionTap': 'Lo único que hay que saber',
  'actionJoke': 'Cuéntame un chiste',
  'actionSos': 'Emergencia',
  'actionAsk': 'Hacer una pregunta',
  'actionSettings': 'Ajustes',
  'actionPrivacy': 'Qué sale de mi teléfono',
  'actionsTitle': 'Lo que Puck puede hacer',
  'actionsOpen': 'Ver todas las acciones',
  'actionsClose': 'Cerrar',
  'actionsHint': 'Todas las acciones de Puck, como botones. Aquí no hace falta '
      'ningún gesto.',
  'sosConfirmTitle': '¿Empezar la cuenta atrás de emergencia?',
  'sosConfirmBody': 'Puck enciende la linterna y abre un mensaje que aún '
      'tienes que enviar tú. Puedes cancelar en cualquier momento.',
  'sosConfirmStart': 'Empezar la cuenta atrás',
  'sosConfirmBack': 'Ahora no',
  'firstRunTitle': 'Cuatro gestos, un botón',
  'firstRunTap': 'Toca — lo único que hay que saber',
  'firstRunDoubleTap': 'Doble toque — un chiste',
  'firstRunHold': 'Mantén pulsado — emergencia',
  'firstRunSwipe': 'Desliza hacia arriba — pregunta lo que quieras',
  'firstRunDismiss': 'Toca esta tarjeta para no volver a verla',
  'labelHappeningNow': 'AHORA MISMO',
  'labelNextUp': 'A CONTINUACIÓN',
  'labelToday': 'HOY',
  'labelBattery': 'BATERÍA',
  'labelWeather': 'TIEMPO',
  'labelGoodMorning': 'BUENOS DÍAS',
  'labelGoodAfternoon': 'BUENAS TARDES',
  'labelGoodEvening': 'BUENAS NOCHES',
  'allDay': 'Todo el día',
  'nothingUrgent': 'nada te necesita ahora mismo.',
  'nothingUrgentNight': 'Nada urgente. Dormir también es un plan.',
  'nothingUrgentLate': 'Nada urgente. Mañana ya está haciendo cola.',
  'clearAhead': 'todo despejado.',
  'wxClear': 'Despejado',
  'wxPartlyCloudy': 'Parcialmente nublado',
  'wxFog': 'Niebla',
  'wxDrizzle': 'Llovizna',
  'wxRain': 'Lluvia',
  'wxSnow': 'Nieve',
  'wxShowers': 'Chubascos',
  'wxSnowShowers': 'Chubascos de nieve',
  'wxThunderstorm': 'Tormenta',
  'headlineStarted': '%1 empezó hace %2',
  'headlineNextUp': '%1 %2',
  'headlineBatteryLow': '%1% — carga antes de salir',
  'headlineBatteryCritical': '%1% — busca un cargador ya',
  'headlineCharged': 'Cargado al %1%',
  'headlineRainStarting': 'Empieza a llover %1 — lleva paraguas',
  'headlineRainAt': 'Lluvia a las %1 — lleva paraguas',
  'headlineCold': '%1° fuera — ponte una chaqueta',
  'headlineHot': '%1° fuera — lleva agua',
  'headlineTime': '%1 — %2',
  'detailCondition': '%1 · %2',
  'countdownNow': 'ahora',
  'countdownIn': 'en %1',
  'unitSeconds': ' s',
  'unitMinutes': ' min',
  'unitHours': ' h',
  'unitDays': ' d',
  'askAnything': 'Pregunta lo que quieras.',
  'intentFieldLabel': 'Tu pregunta',
  'micStart': 'Di tu pregunta',
  'micStop': 'Dejar de escuchar',
  'sendAnswer': 'Preguntar',
  'thinking': 'Pensando',
  'answerComplete': 'Respuesta completa',
  'sosCancel': 'CANCELAR',
  'sosStop': 'PARAR',
  'sosCancelHint': 'Cancela la emergencia. No se envía nada.',
  'sosStopHint': 'Apaga la linterna y cierra esta pantalla.',
  'sosGettingLocation': 'Obteniendo tu ubicación',
  'sosLocationFound': 'Ubicación encontrada',
  'sosLocationMissing': 'Sin GPS — el mensaje lo dirá',
  'sosNoContact': 'Sin contacto — llama directamente',
  'sosMessageReady': 'Mensaje listo — pulsa enviar',
  'sosNoMessagingApp': 'Sin app de mensajes — llama directamente',
  'sosDialerOpen': 'Marcador abierto — pulsa llamar',
  'sosNoDialer': 'Este dispositivo no tiene marcador',
  'sosCounting': 'SOS en %1',
  'sosCountingAnnouncement': 'SOS en %1 segundos. Levanta el dedo para cancelar.',
  'sosRingWaiting': 'Esperando la ubicación',
  'sosRingFound': 'Ubicación encontrada',
  'sosEmergencyFallbackNote': 'Número de emergencias local. Abre el marcador: '
      'no se llama por ti.',
  'sosEmergencyRegionalNote': 'No se pudo leer tu región, así que este es el '
      'número de emergencias estándar. Abre el marcador: no se llama por ti.',
  'callEmergency': 'LLAMAR %1',
  'callEmergencySemantics': 'Llamar a emergencias, %1',
  'settingsTitle': 'Ajustes',
  'back': 'Atrás',
  'holdTitle': 'Mantener pulsado para una emergencia',
  'holdOneSecond': '1 segundo',
  'holdTwoSeconds': '2 segundos',
  'holdThreeSeconds': '3 segundos',
  'holdNote': 'Tres segundos es lo predeterminado y lo más seguro. Acórtalo '
      'solo si te cuesta mantener pulsado tanto tiempo.',
  'emergencyContactTitle': 'Contacto de emergencia',
  'emergencyContactHint': 'Número',
  'emergencyContactNote': 'El mensaje de SOS se abre en Mensajes, listo para '
      'enviar. Nunca se envía solo. Sin contacto, Puck ofrece el número de '
      'emergencias local.',
  'advancedTitle': 'Avanzado',
  'advancedNote': 'Puck responde por sí solo con un servicio compartido. No hay '
      'nada que configurar.',
  'apiKeyTitle': 'Usar mi propia clave (opcional)',
  'apiKeyHint': 'Pega una clave',
  'paste': 'Pegar',
  'apiKeyNote': 'Opcional y avanzado. Con tu propia clave, las respuestas '
      'vienen directamente de tu cuenta de Groq y no se usa el servicio '
      'compartido.',
  'releaseCancelsOne': 'Puck se cancela solo cuando sueltas antes de tiempo. '
      'Lo ha hecho %1 vez.',
  'releaseCancelsMany': 'Puck se cancela solo cuando sueltas antes de tiempo. '
      'Lo ha hecho %1 veces.',
  'cloudTitle': 'Dejar que Puck responda con internet',
  'cloudNote': 'Apagado significa que ninguna pregunta, y nada más, sale de tu '
      'teléfono. La tarjeta, el chiste, los dados y la emergencia siguen '
      'funcionando.',
  'privacyTitle': 'Qué sale de tu teléfono',
  'privacyNote': 'La lista, en palabras claras, antes de activar nada.',
  'clearDataTitle': 'Borrar todo lo que Puck guardó',
  'clearDataAction': 'Borrar datos locales',
  'clearDataConfirm': '¿Borrar? No se puede deshacer.',
  'clearDataDone': 'Borrado.',
  'clearDataCancel': 'Conservar',
  'diagnosticsTitle': 'Diagnóstico',
  'diagnosticsVersion': 'Versión',
  'diagnosticsPlatform': 'Plataforma',
  'diagnosticsCloud': 'Respuestas en la nube',
  'diagnosticsCloudOn': 'activadas',
  'diagnosticsCloudOff': 'desactivadas',
  'diagnosticsSpeech': 'Entrada por voz',
  'diagnosticsUnavailable': 'no disponible',
  'diagnosticsAvailable': 'disponible',
  'feedbackTitle': 'Escribir al autor',
  'feedbackNote': 'Abre tu app de correo con la versión y un bloque de estado. '
      'No incluye datos personales.',
  'feedbackAction': 'Enviar comentarios',
  'feedbackNoMail': 'No hay app de correo en este dispositivo.',
  'privacyScreenTitle': 'Qué sale de tu teléfono',
  'privacyIntro': 'Puck solo envía algo cuando le pides que responda a una '
      'pregunta. Esta es la lista completa.',
  'privacySendsTitle': 'Se envía con una pregunta',
  'privacyQuestion': 'La pregunta que escribiste o dijiste.',
  'privacyEventTitle': 'El título de tu próximo evento, si hay uno cerca.',
  'privacyEventWhen': 'Si ese evento ya empezó y cuánto falta para que empiece.',
  'privacyEventWhere': 'El lugar del evento, si la entrada tiene uno.',
  'privacyBattery': 'Tu nivel de batería y si se está cargando.',
  'privacyWeather': 'La temperatura y el tiempo actuales donde estás, de '
      'Open-Meteo.',
  'privacyTime': 'Tu hora local.',
  'privacyDeviceId': 'Un identificador aleatorio de esta instalación, usado '
      'solo para contar solicitudes y que un teléfono no consuma todo. Puedes '
      'restablecerlo cuando quieras.',
  'privacyNeverTitle': 'Nunca se envía',
  'privacyNeverBody': 'Ni coordenadas, ni contactos, ni mensajes, ni el '
      'contenido del calendario, ni tu nombre, ni tu correo, ni el '
      'identificador publicitario. No hay cuenta, ni analíticas, ni informes '
      'de fallos.',
  'privacyAttribution': 'Datos meteorológicos de Open-Meteo (CC BY 4.0). '
      'Respuestas de Groq. Aparecen aquí porque ambos pueden ver lo de arriba.',
  'coinHeads': 'Cara.',
  'coinTails': 'Cruz.',
  'sosMessage': 'Necesito ayuda.',
  'sosMessageNoLocation': 'Ubicación no disponible.',
  'callEmergencyHint': 'Abre el marcador con el número listo. '
      'Tú pulsas llamar.',
  'busyLabel': 'Ocupado',
  'offlineLine': 'Sin conexión. Prueba moneda, dados o cuentas.',
  'answerKeyRejected': 'Esa clave fue rechazada. Arréglala o bórrala en '
      'Ajustes; moneda, dados y cuentas siguen funcionando.',
  'safetyLine': 'No puedo ayudarte con esto. Llama ahora a un número de '
      'emergencias o a una línea de crisis.',
  'jokeFallback': 'Los chistes, por ahora, solo funcionan en inglés. El botón '
      'no.',
};

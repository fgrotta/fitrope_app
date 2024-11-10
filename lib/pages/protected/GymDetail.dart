import 'package:fitrope_app/style.dart';
import 'package:fitrope_app/types/gym.dart';
import 'package:flutter/material.dart';
import 'package:flutter_design_system/components/calendar.dart';

class GymDetail extends StatefulWidget {
  final Gym gym;
  const GymDetail({super.key, required this.gym});

  @override
  State<GymDetail> createState() => _GymDetailState();
}

class _GymDetailState extends State<GymDetail> {
  DateTime firstDate = DateTime(DateTime.now().year);
  DateTime lastDate = DateTime(DateTime.now().year + 2);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: primaryColor,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(widget.gym.name, style: const TextStyle(color: Colors.white),),
      ),
      backgroundColor: backgroundColor,
      body: Column(
        children: [
          Theme(
            data: ThemeData(
              datePickerTheme: DatePickerThemeData(
                dayForegroundColor: WidgetStateProperty.all(Colors.white),
                weekdayStyle: const TextStyle(color: Colors.white),
                headerHeadlineStyle: const TextStyle(color: Colors.white),
                todayForegroundColor: WidgetStateProperty.all(Colors.white),
                todayBackgroundColor: WidgetStateProperty.all(const Color.fromARGB(255, 90, 90, 90)),
                dayBackgroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return const Color.fromARGB(255, 100, 100, 100);
                  }
                  return null;
                }),)
            ), 
            child: Calendar(
              onDateChanged: (DateTime value) {  }, 
              initialDate: DateTime.now(), 
              firstDate: firstDate, 
              lastDate: lastDate,
            ),
          ),
        ],
      ),
    );
  }
}
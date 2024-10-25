import 'package:fitrope_app/api/getGyms.dart';
import 'package:fitrope_app/style.dart';
import 'package:fitrope_app/types/gym.dart';
import 'package:flutter/material.dart';
import 'package:flutter_design_system/components/custom_card.dart';

class GymsPage extends StatefulWidget {
  const GymsPage({super.key});

  @override
  State<GymsPage> createState() => _GymsPageState();
}

class _GymsPageState extends State<GymsPage> {

  List<Gym> gyms = [];

  @override
  void initState() {
    super.initState();

    getGyms().then((List<Gym> response) {
      setState(() {
        gyms = response;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(pagePadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Palestre', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 30),),
          const SizedBox(height: 20,),
          ...gyms.map((Gym gym) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: CustomCard(title: gym.name),
          ))
        ],
      ),
    );
  }
}
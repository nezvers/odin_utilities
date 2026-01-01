// olc_geometry2d.cpp : This file contains the 'main' function. Program execution begins and ends there.
//

#include <iostream>
#include <vector>
#include "olcUTIL_Geometry2D.h"

using namespace olc::utils::geom2d;

int main()
{
    const line<float> l{ {1000.f, 3000.f}, {5000.f, 3000.f} };
    const line<float> left{ {2000.f, 2000.f}, {2000.f, 4000.f} };

    std::vector<olc::v_2d<float>> intersection = intersects(left, l, false);

    std::cout << "Hello World!\n";
}

// Run program: Ctrl + F5 or Debug > Start Without Debugging menu
// Debug program: F5 or Debug > Start Debugging menu

// Tips for Getting Started: 
//   1. Use the Solution Explorer window to add/manage files
//   2. Use the Team Explorer window to connect to source control
//   3. Use the Output window to see build output and other messages
//   4. Use the Error List window to view errors
//   5. Go to Project > Add New Item to create new code files, or Project > Add Existing Item to add existing code files to the project
//   6. In the future, to open this project again, go to File > Open > Project and select the .sln file
